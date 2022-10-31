require 'expcalc'
require 'json'
require 'colorize'


class Ontology
    #########################################################
    # AUTHOR NOTES
    #########################################################

    # 2 - Items values (not keys) are imported as strings, not as symbols (maybe add a flag which indicates if values are, or not, symbols?) 

    #############################################
    # FIELDS
    #############################################
    # Handled object variables
    # => @terms :: OBO terms descriptions
    # => @ancestors_index :: hash of ancestors per each term handled with any structure relationships
    # => @descendants_index :: hash of descendants per each term handled with any structure relationships
    # => @alternatives_index :: has of alternative IDs (include alt_id and obsoletes)
    # => @obsoletes_index :: hash of obsoletes and it's new ids
    # => @structureType :: type of ontology structure depending on ancestors relationship. Allowed: {atomic, sparse, circular, hierarchical}
    # => @ics :: already calculated ICs for handled terms and IC types
    # => @meta :: meta_information about handled terms like [ancestors, descendants, struct_freq, observed_freq]
    # => @max_freqs :: maximum freqs found for structural and observed freqs
    # => @dicts :: bidirectional dictionaries with three levels <key|value>: 1º) <tag|hash2>; 2º) <(:byTerm/:byValue)|hash3>; 3º) dictionary <k|v>
    # => @profiles :: set of terms assigned to an ID
    # => @items :: hash with items relations to terms
    # => @removable_terms :: array of terms to not be considered
    # => @term_paths :: metainfo about parental paths of each term

    @@allowed_calcs = {ics: [:resnik, :resnik_observed, :seco, :zhou, :sanchez], sims: [:resnik, :lin, :jiang_conrath]}

attr_accessor :terms, :ancestors_index, :descendants_index, :alternatives_index, :obsoletes_index, :obsoletes, :structureType, :ics, :max_freqs, :meta, :dicts, :profiles, :items, :term_paths, :reroot
    
    #############################################
    # CONSTRUCTOR
    #############################################
    
    # Instantiate a OBO_Handler object
    # ===== Parameters
    # +file+:: with info to be loaded (.obo ; .json)
    # +load_file+:: activate load process automatically
    # +removable_terms+: term to be removed from calcs
    # +build+: flag to launch metainfo calculation
    # +file_format+: force format type despite file extension. Can be :obo or :json
    def initialize(file: nil, load_file: false, removable_terms: [], build: true, file_format: nil, extra_dicts: [])
        # Initialize object variables
        @terms = {}
        @ancestors_index = {}
        @descendants_index = {}
        @alternatives_index = {}
        # TODO: Revise the use of the following obsolete indexes that is correct, first one mus be used to pas from obsolete to alt_id but the secon must be used to check if a term is obsolete or not
        @obsoletes_index = {} # obsolete id to alteranative id
        @obsoletes = {} # id is obsolete but it could or not have an alt id
        @structureType = nil
        @ics = Hash[@@allowed_calcs[:ics].map{|ictype| [ictype, {}]}]
        @meta = {}
        @max_freqs = {:struct_freq => -1.0, :observed_freq => -1.0, :max_depth => -1.0}
        @dicts = {}
        @profiles = {}
        @items = {}
        @term_paths = {}
        @reroot = false
        load_file = true unless file.nil? # This should remove load_file argument, keep it for old scripts
        # Load if proceeds
        if load_file
            fformat = file_format
            fformat = File.extname(file) if fformat.nil? && !file.nil?
            if fformat == :obo || fformat == ".obo"
                OboParser.load(self, file, build: build, black_list: removable_terms, extra_dicts: extra_dicts)
            elsif fformat == :json || fformat == ".json"
                JsonParser.load(self, file, build: build)
            elsif !fformat.nil?
                warn 'Format not allowed. Loading process will not be performed'
            end
            precompute if build
        end
    end


    #############################################
    # CLASS METHODS
    #############################################

    # ===== Parameters
    # +root+:: main term to expand
    # +ontology+:: to be cutted
    # +clone+:: if true, given ontology object will not be mutated
    # +remove_up+:: if true, stores only the root term given an it descendants. If false, only root ancestors will be stored
    # ===== Returns
    # An Ontology object with terms after cut the ontology.
    def self.mutate(root, ontology, clone: true, remove_up: true)
        ontology = ontology.clone if clone
        # Obtain affected IDs
        descendants = ontology.descendants_index[root]
        descendants << root # Store itself to do not remove it
        # Remove unnecesary terms
        terms = ontology.terms.select{|id,v| remove_up ? descendants.include?(id) : !descendants.include?(id)}
        ids = terms.keys
        terms.each do |id, term|
            term[:is_a] = term[:is_a] & ids # Clean parental relations to keep only whose that exist between selected terms
        end
        ontology.terms = terms
        ontology.ics = Hash[@@allowed_calcs[:ics].map{|ictype| [ictype, {}]}]
        ontology.max_freqs = {:struct_freq => -1.0, :observed_freq => -1.0, :max_depth => -1.0}
        ontology.dicts = {}
        ontology.term_paths = {}
        ontology.reroot = true

        ontology.ancestors_index = {}
        ontology.descendants_index = {}
        ontology.alternatives_index = {}
        ontology.obsoletes_index = {}
        ontology.meta = {}
        ontology.profiles = {}
        ontology.items = {}


        # Recalculate metadata
        ontology.build_index
        ontology.add_observed_terms_from_profiles
        # Finish
        return ontology
    end



    #############################################
    # GENERAL METHODS
    #############################################

    # Increase observed frequency for a specific term
    # ===== Parameters
    # +term+:: term which frequency is going to be increased
    # +increas+:: frequency rate to be increased. Default = 1
    # ===== Return
    # true if process ends without errors, false in other cases
    def add_observed_term(term:,increase: 1.0)
        return false unless term_exist?(term)
        # Check if exists
        @meta[term] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:observed_freq => 0.0} if @meta[term].nil?
        # Add frequency
        @meta[term][:observed_freq] = 0 if @meta[term][:observed_freq] == -1
        @meta[term][:observed_freq] += increase
        # Check maximum frequency
        @max_freqs[:observed_freq] = @meta[term][:observed_freq] if @max_freqs[:observed_freq] < @meta[term][:observed_freq]  
        return true
    end


    # Increase the arbitrary frequency of a given term set 
    # ===== Parameters
    # +terms+:: set of terms to be updated
    # +increase+:: amount to be increased
    # +transform_to_sym+:: if true, transform observed terms to symbols. Default: false
    # ===== Return
    # true if process ends without errors and false in other cases
    def add_observed_terms(terms:, increase: 1.0, transform_to_sym: false)
        return terms.map{|id| self.add_observed_term(
            term: transform_to_sym ? id.to_sym : id, 
            increase: increase)}
    end


    # Compare to terms sets 
    # ===== Parameters
    # +termsA+:: set to be compared
    # +termsB+:: set to be compared
    # +sim_type+:: similitude method to be used. Default: resnik
    # +ic_type+:: ic type to be used. Default: resnik
    # +bidirectional+:: calculate bidirectional similitude. Default: false
    # ===== Return
    # similitude calculated
    def compare(termsA, termsB, sim_type: :resnik, ic_type: :resnik, bidirectional: true, store_mica: false)
        # Check
        raise ArgumentError, "Terms sets given are NIL" if termsA.nil? | termsB.nil?
        raise ArgumentError, "Set given is empty. Aborting similarity calc" if termsA.empty? | termsB.empty?
        micasA = []
        # Compare A -> B
        termsA.each do |tA|
            micas = []
            termsB.each do |tB|
                if store_mica
                    value = @mica_index[tA][tB]
                else
                    value = self.get_similarity(tA, tB, type: sim_type, ic_type: ic_type)
                end
                micas << value if value.class == Float 
            end
            !micas.empty? ? micasA << micas.max : micasA << 0 
        end
        means_sim = micasA.sum.fdiv(micasA.size)
        # Compare B -> A
        if bidirectional
            means_simA = means_sim * micasA.size
            means_simB = self.compare(termsB, termsA, sim_type: sim_type, ic_type: ic_type, bidirectional: false, store_mica: store_mica) * termsB.size
            means_sim = (means_simA + means_simB).fdiv(termsA.size + termsB.size)
        end
        # Return
        return means_sim
    end

    # Compare internal stored profiles against another set of profiles. If an external set is not provided, internal profiles will be compared with itself 
    # ===== Parameters
    # +external_profiles+:: set of external profiles. If nil, internal profiles will be compared with itself
    # +sim_type+:: similitude method to be used. Default: resnik
    # +ic_type+:: ic type to be used. Default: resnik
    # +bidirectional+:: calculate bidirectional similitude. Default: false
    # ===== Return
    # Similitudes calculated
    def compare_profiles(external_profiles: nil, sim_type: :resnik, ic_type: :resnik, bidirectional: true)
        profiles_similarity = {} #calculate similarity between patients profile
        if external_profiles.nil?
            comp_profiles = @profiles
            main_profiles = comp_profiles
        else
            comp_profiles = external_profiles
            main_profiles = @profiles
        end
        # Compare
        #@lca_index = {}
        pair_index = get_pair_index(main_profiles, comp_profiles)
        #get_lca_index(pair_index)
        @mica_index = {}
        get_mica_index_from_profiles(pair_index, sim_type: sim_type, ic_type: ic_type, lca_index: false)
        main_profiles.each do |curr_id, current_profile|
            comp_profiles.each do |id, profile|
                value = compare(current_profile, profile, sim_type: sim_type, ic_type: ic_type, bidirectional: bidirectional, store_mica: true)
                add2nestHash(profiles_similarity, curr_id, id, value)
            end    
        end
        return profiles_similarity
    end

    def get_pair_index(profiles_A, profiles_B)
        pair_index = {}
        profiles_A.each do |curr_id, profile_A|
            profiles_B.each do |id, profile_B|
                profile_A.each do |term_A|
                    profile_B.each do |term_B|
                        pair_index[[term_A, term_B].sort] = true 
                    end
                end
            end    
        end
        return pair_index
    end

    ################ get lca index ##################################
    # TODO: VErify an algorith for DAG
    def get_lca_index(pair_index)
        graph, name2num, num2name = get_numeric_graph(@descendants_index)
        queries = {}
        pair_index.each do |ids, val|
            u, v = ids
            u = name2num[u]
            v = name2num[v]
            add2hash(queries, u, v)
            add2hash(queries, v, u)
        end
        roots = get_root
        roots = roots.map{|r| name2num[r]}
        compute_LCAs(queries, graph, roots, num2name)
    end

    def compute_LCAs(queries, net, roots, num2name)
        #https://cp-algorithms.com/graph/lca_tarjan.html
        roots.each do |r|
            ancestor = []
            visited = [] # true
            dfs(r, net, ancestor, visited, queries, num2name)
        end
    end

    def find_set(v, ancestor) 
        parent = ancestor[v]
        return v if v == parent
        return find_set(parent, ancestor)
    end

    def union_sets(a, b, ancestor) 
        a = find_set(a, ancestor)
        b = find_set(b, ancestor)
        ancestor[b] = a if (a != b)
    end

    def dfs(v, net, ancestor, visited, queries, num2name)
        visited[v] = true
        ancestor[v] = v
        connected_nodes_v = net[v]
        if !connected_nodes_v.nil?
            connected_nodes_v.each do |u|
                if visited[u].nil?
                    dfs(u, net, ancestor, visited, queries, num2name)
                    union_sets(v, u, ancestor)
                    ancestor[find_set(v, ancestor)] = v
                end
            end
        end
        v_node_queries = queries[v]
        if !v_node_queries.nil?
            v_node_queries.each do |other_node|
                if visited[other_node]
                    lca = ancestor[find_set(other_node, ancestor)]
                    v = num2name[v]
                    other_node = num2name[other_node]
                    lca = num2name[lca]
                    add2nestHash(@lca_index, v, other_node, lca)
                    add2nestHash(@lca_index, other_node, v, lca)
                end
            end
        end
    end

    def get_numeric_graph(graph)
        id_index = {}
        num2name = {}
        num_graph = {}
        count = 0
        graph.each do |node, connecte_nodes|
            node_id = id_index[node]
            if node_id.nil?
                node_id = count
                id_index[node] = node_id
                num2name[node_id] = node
                count += 1
            end
            new_cn_ids = []
            connecte_nodes.each do |cn|
                cn_id = id_index[cn]
                if cn_id.nil?
                    cn_id = count
                    id_index[cn] = cn_id
                    num2name[cn_id] = cn
                    count += 1
                end
                new_cn_ids << cn_id
            end
            num_graph[node_id] = new_cn_ids
        end
        return num_graph, id_index, num2name
    end

    ##################################################
    
    def get_mica_index_from_profiles(pair_index, sim_type: :resnik, ic_type: :resnik, lca_index: true)
        pair_index.each do |pair, val|
            tA, tB = pair
            value = self.get_similarity(tA, tB, type: sim_type, ic_type: ic_type, lca_index: lca_index)
            value = true if value.nil? # We use true to save that the operation was made but there is not mica value
            add2nestHash(@mica_index, tA, tB, value)
            add2nestHash(@mica_index, tB, tA, value)
        end
    end

    def precompute
        get_index_frequencies
        calc_term_levels(calc_paths: true)
    end


    # Calculates regular frequencies based on ontology structure (using parentals)
    # ===== Returns 
    # true if everything end without errors and false in other cases
    def get_index_frequencies()
        # Check
        if @ancestors_index.empty?
            warn('ancestors_index object is empty')
        else
            # Per each term, add frequencies
            each(att = true, only_main = false) do |id, tags| # if only_main is true, the code and tests fails. This is not logical
                if !@alternatives_index.include?(id) # Official term
                    query = @meta[id] # Check if exist
                    if query.nil?
                        query = {ancestors: 0.0, descendants: 0.0, struct_freq: 0.0, observed_freq: 0.0}
                        @meta[id] = query 
                    end
                    # Store metadata
                    query[:ancestors] = @ancestors_index.include?(id) ? @ancestors_index[id].count{|anc| !@alternatives_index.include?(anc)}.to_f : 0.0
                    query[:descendants] = @descendants_index.include?(id) ? @descendants_index[id].count{|desc| !@alternatives_index.include?(desc)}.to_f : 0.0
                    query[:struct_freq] = query[:descendants] + 1.0
                    # Update maximums
                    @max_freqs[:struct_freq] = query[:struct_freq] if @max_freqs[:struct_freq] < query[:struct_freq]  
                    @max_freqs[:max_depth] = query[:descendants] if @max_freqs[:max_depth] < query[:descendants]  
                end
            end
        end
    end

    # Find ancestors of a given term
    # ===== Parameters
    # +term+:: to be checked
    # +filter_alternatives+:: if true, remove alternatives from final results
    # ===== Returns 
    # an array with all ancestors of given term or false if parents are not available yet
    def get_ancestors(term, filter_alternatives = false)
        return self.get_familiar(term, true, filter_alternatives)        
    end


    # Find descendants of a given term
    # ===== Parameters
    # +term+:: to be checked
    # +filter_alternatives+:: if true, remove alternatives from final results
    # ===== Returns 
    # an array with all descendants of given term or false if parents are not available yet
    def get_descendants(term, filter_alternatives = false)
        return self.get_familiar(term, false, filter_alternatives)        
    end


    # Find ancestors/descendants of a given term
    # ===== Parameters
    # +term+:: to be checked
    # +return_ancestors+:: return ancestors if true or descendants if false
    # +filter_alternatives+:: if true, remove alternatives from final results
    # ===== Returns 
    # an array with all ancestors/descendants of given term or nil if parents are not available yet
    def get_familiar(term, return_ancestors = true, filter_alternatives = false)
        # Find into parentals
        familiars = return_ancestors ? @ancestors_index[term] : @descendants_index[term]    
        if !familiars.nil?
            familiars = familiars.clone
            if filter_alternatives
                familiars.reject!{|fm| @alternatives_index.include?(fm)}
            end
        else
            familiars = []
        end
        return familiars
    end


    # Obtain IC of an specific term
    # ===== Parameters
    # +term+:: which IC will be calculated
    # +type+:: of IC to be calculated. Default: resnik
    # +force+:: force re-calculate the IC. Do not check if it is already calculated
    # +zhou_k+:: special coeficient for Zhou IC method
    # ===== Returns 
    # the IC calculated
    def get_IC(termRaw, type: :resnik, force: false, zhou_k: 0.5)
        term = termRaw.to_sym
        curr_ics = @ics[type]
        # Check 
        raise ArgumentError, "IC type specified (#{type}) is not allowed" if !@@allowed_calcs[:ics].include?(type)
        # Check if it's already calculated
        return curr_ics[term] if (curr_ics.include? term) && !force
        # Calculate
        ic = - 1
        term_meta = @meta[term]
        case type # https://arxiv.org/ftp/arxiv/papers/1310/1310.8059.pdf  |||  https://sci-hub.st/https://doi.org/10.1016/j.eswa.2012.01.082
            ###########################################
            #### STRUCTURE BASED METRICS
            ###########################################
            # Shortest path
            # Weighted Link
            # Hirst and St-Onge Measure
            # Wu and Palmer
            # Slimani
            # Li
            # Leacock and Chodorow
            ###########################################
            #### INFORMATION CONTENT METRICS
            ###########################################
            when :resnik # Resnik P: Using Information Content to Evaluate Semantic Similarity in a Taxonomy
                # -log(Freq(x) / Max_Freq)
                ic = -Math.log10(term_meta[:struct_freq].fdiv(@max_freqs[:struct_freq]))
            when :resnik_observed 
                # -log(Freq(x) / Max_Freq)
                ic = -Math.log10(term_meta[:observed_freq].fdiv(@max_freqs[:observed_freq]))
            # Lin
            # Jiang & Conrath

            ###########################################
            #### FEATURE-BASED METRICS
            ###########################################
            # Tversky
            # x-similarity
            # Rodirguez

            ###########################################
            #### HYBRID METRICS
            ###########################################
            when :seco, :zhou # SECO:: An intrinsic information content metric for semantic similarity in WordNet
                #  1 - ( log(hypo(x) + 1) / log(max_nodes) )
                ic = 1 - Math.log10(term_meta[:struct_freq]).fdiv(Math.log10(@terms.length - @alternatives_index.length))
                if :zhou # New Model of Semantic Similarity Measuring in Wordnet                
                    # k*(IC_Seco(x)) + (1-k)*(log(depth(x))/log(max_depth))
                    @ics[:seco][term] = ic # Special store
                    ic = zhou_k * ic + (1.0 - zhou_k) * (Math.log10(term_meta[:descendants]).fdiv(Math.log10(@max_freqs[:max_depth])))
                end
            when :sanchez # Semantic similarity estimation in the biomedical domain: An ontology-basedinformation-theoretic perspective
                ic = -Math.log10((term_meta[:descendants].fdiv(term_meta[:ancestors]) + 1.0).fdiv(@max_freqs[:max_depth] + 1.0))
            # Knappe
        end            
        curr_ics[term] = ic
        return ic
    end


    # Calculates and return resnik ICs (by ontology and observed frequency) for observed terms
    # ===== Returns 
    # two hashes with resnik and resnik_observed ICs for observed terms
    def get_observed_ics_by_onto_and_freq() # NEED TEST
        ic_ont = {}
        resnik_observed = {}
        observed_terms = @profiles.values.flatten.uniq
        observed_terms.each do |term| 
            ic_ont[term] = get_IC(term)
            resnik_observed[term] = get_IC(term, type: :resnik_observed)
        end
        return resnik, resnik_observed
    end


    # Find the IC of the Most Index Content shared Ancestor (MICA) of two given terms
    # ===== Parameters
    # +termA+:: term to be cheked
    # +termB+:: term to be checked
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the IC of the MICA(termA,termB)
    def get_ICMICA(termA, termB, ic_type = :resnik) # NEED TEST
        term, ic = self.get_MICA(termA, termB, ic_type)
        return term.nil? ? nil : ic
    end


    # Find the Most Index Content shared Ancestor (MICA) of two given terms
    # ===== Parameters
    # +termA+:: term to be cheked
    # +termB+:: term to be checked
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the MICA(termA,termB) and it's IC
    def get_MICA(termA, termB, ic_type = :resnik, lca_index = false)
        termA = @alternatives_index[termA] if @alternatives_index.include?(termA)
        termB = @alternatives_index[termB] if @alternatives_index.include?(termB)
        mica = [nil,-1.0]
        # Special case
        if termA.eql?(termB)
            ic = self.get_IC(termA, type: ic_type)
            mica = [termA, ic]
        else    
            get_LCA(termA, termB, lca_index: lca_index).each do |lca| # Find MICA in shared ancestors
                ic = self.get_IC(lca, type: ic_type)
                mica = [lca, ic] if ic > mica[1]
            end
        end
        return mica
    end

    def get_LCA(termA, termB, lca_index: false)
        lca = []
        if lca_index
            res = @lca_index.dig(termA, termB)
            lca = [res] if !res.nil?
        else
            # Obtain ancestors (include itselfs too)
            anc_A = self.get_ancestors(termA) 
            anc_B = self.get_ancestors(termB)
            if !(anc_A.empty? && anc_B.empty?)
                anc_A << termA
                anc_B << termB
                lca = anc_A & anc_B
            end
        end
        return lca
    end


    # Calculate similarity between two given terms
    # ===== Parameters
    # +termsA+:: to be compared
    # +termsB+:: to be compared
    # +type+:: similitude formula to be used
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the similarity between both sets or false if frequencies are not available yet
    def get_similarity(termA, termB, type: :resnik, ic_type: :resnik, lca_index: false)
        # Check
        raise ArgumentError, "SIM type specified (#{type}) is not allowed" if !@@allowed_calcs[:sims].include?(type)
        sim = nil
        mica, sim_res = get_MICA(termA, termB, ic_type, lca_index)
        if !mica.nil?
            case type
                when :resnik
                    sim = sim_res
                when :lin
                    sim = (2.0 * sim_res).fdiv(self.get_IC(termA,type: ic_type) + self.get_IC(termB,type: ic_type))
                when :jiang_conrath # This is not a similarity, this is a disimilarity (distance)
                    sim = (self.get_IC(termA, type: ic_type) + self.get_IC(termB, type: ic_type)) - (2.0 * sim_res)
            end
        end
        return sim
    end

    # Exports an OBO_Handler object in json format
    # ===== Parameters
    # +file+:: where info will be stored
    def write(file)
        # Take object stored info
        obj_info = {terms: @terms,
                    ancestors_index: @ancestors_index,
                    descendants_index: @descendants_index,
                    alternatives_index: @alternatives_index,
                    obsoletes_index: @obsoletes_index,
                    structureType: @structureType,
                    ics: @ics,
                    meta: @meta,
                    max_freqs: @max_freqs,
                    dicts: @dicts,
                    profiles: @profiles,
                    items: @items,
                    term_paths: @term_paths}
        # Convert to JSON format & write
        File.open(file, "w") { |f| f.write obj_info.to_json }
    end

    # Translate a given value using an already calcualted dictionary
    # ===== Parameters
    # +toTranslate+:: value to be translated using dictiontionary
    # +tag+:: used to generate the dictionary
    # +byValue+:: boolean flag to indicate if dictionary must be used values as keys or terms as keys. Default: values as keys = true
    # ===== Return
    # translation
    def translate(toTranslate, tag, byValue: true)
        dict = byValue ? @dicts[tag][:byValue] : @dicts[tag][:byTerm]    
        toTranslate =  get_main_id(toTranslate) if !byValue
        return dict[toTranslate]
    end

    # Translate a name given
    # ===== Parameters
    # +name+:: to be translated
    # ===== Return
    # translated name or nil if it's not stored into this ontology
    def translate_name(name)
        term = self.translate(name, :name)
        term = self.translate(name, :synonym) if term.nil?
        return term            
    end

    # Translate several names and return translations and a list of names which couldn't be translated
    # ===== Parameters
    # +names+:: array to be translated
    # ===== Return
    # two arrays with translations and names which couldn't be translated respectively
    def translate_names(names)
        translated = []
        rejected = []
        names.each do |name|
            tr = self.translate_name(name)
            if tr.nil?
                rejected << name
            else
                translated << tr
            end
        end
        return translated, rejected
    end


    # Translates a given ID to it assigned name
    # ===== Parameters
    # +id+:: to be translated
    # ===== Return
    # main name or nil if it's not included into this ontology
    def translate_id(id)
        name = self.translate(id, :name, byValue: false)
        return name.nil? ? nil : name.first
    end


    # Translates several IDs and returns translations and not allowed IDs list
    # ===== Parameters
    # +ids+:: to be translated
    # ===== Return
    # two arrays with translations and names which couldn't be translated respectively
    def translate_ids(ids)
        translated = []
        rejected = []
        ids.each do |term_id|
            tr = self.translate_id(term_id.to_sym)
            if !tr.nil?
                translated << tr
            else
                rejected << tr
            end
        end
        return translated, rejected
    end


    # ===== Returns 
    # the main ID assigned to a given ID. If it's a non alternative/obsolete ID itself will be returned
    # ===== Parameters
    # +id+:: to be translated
    # ===== Return
    # main ID related to a given ID. Returns nil if given ID is not an allowed ID
    def get_main_id(id) # TODO extend to recursively check if the obtained mainID is an alternative ID again and use it in a new query until get a real mainID
        mainID = @alternatives_index[id]
        return nil if !term_exist?(id) && mainID.nil? && !@obsoletes_index.include?(id)
        new_id = id
        new_id = mainID if !mainID.nil? && !@obsoletes_index.include?(mainID)
        return new_id
    end


    # Check a pull of IDs and return allowed IDs removing which are not official terms on this ontology
    # ===== Parameters
    # +ids+:: to be checked
    # ===== Return
    # two arrays whit allowed and rejected IDs respectively
    def check_ids(ids, substitute: true)
        checked_codes = []
        rejected_codes = []
        ids.each do |id|
            new_id = get_main_id(id)
            if new_id.nil?
                rejected_codes << id
            else
                if substitute
                    checked_codes << new_id
                else
                    checked_codes << id
                end
            end
        end
        return checked_codes, rejected_codes
    end

    def term_exist?(id)
        return @terms.include?(id)
    end


    # Stores a given profile with an specific ID. If ID is already assigend to a profile, it will be replaced
    # ===== Parameters
    # +id+:: assigned to profile
    # +terms+:: array of terms
    # +substitute+:: subsstitute flag from check_ids
    def add_profile(id, terms, substitute: true)
        warn("Profile assigned to ID (#{id}) is going to be replaced") if @profiles.include? id
        correct_terms, rejected_terms = self.check_ids(terms, substitute: substitute)
        if !rejected_terms.empty?
            warn("Given terms contains erroneus IDs: #{rejected_terms.join(",")}. These IDs will be removed")
        end
        if id.is_a? Numeric
            @profiles[id] = correct_terms              
        else
            @profiles[id.to_sym] = correct_terms  
        end
    end    


    # Method used to store a pool of profiles
    # ===== Parameters
    # +profiles+:: array/hash of profiles to be stored. If it's an array, numerical IDs will be assigned starting at 1 
    # +calc_metadata+:: if true, launch get_items_from_profiles process
    # +reset_stored+:: if true, remove already stored profiles
    # +substitute+:: subsstitute flag from check_ids
    def load_profiles(profiles, calc_metadata: true, reset_stored: false, substitute: false)
        self.reset_profiles if reset_stored
        # Check
        if profiles.kind_of?(Array)
            profiles.each_with_index do |items, i|
                self.add_profile(i, items.map {|item| item.to_sym}, substitute: substitute)
            end
        else # Hash
            if !profiles.keys.select{|id| @profiles.include?(id)}.empty?
                warn('Some profiles given are already stored. Stored version will be replaced')
            end
            profiles.each{|id, prof| self.add_profile(id, prof, substitute: substitute)}
        end

        self.add_observed_terms_from_profiles(reset: true)

        if calc_metadata
            self.get_items_from_profiles
        end
    end


    # Internal method used to remove already stored profiles and restore observed frequencies
    def reset_profiles
        # Clean profiles storage
        @profiles = {}
        # Reset frequency observed
        @meta.each{|term,info| info[:observed_freq] = 0}
        @max_freqs[:observed_freq] = 0
    end


    # ===== Returns 
    # profiles assigned to a given ID
    # ===== Parameters
    # +id+:: profile ID
    # ===== Return
    # specific profile or nil if it's not stored
    def get_profile(id)
        return @profiles[id]
    end    


    # ===== Returns 
    # an array of sizes for all stored profiles
    # ===== Return
    # array of profile sizes
    def get_profiles_sizes()
        return @profiles.map{|id,terms| terms.length}
    end


    # ===== Returns 
    # mean size of stored profiles
    # ===== Parameters
    # +round_digits+:: number of digits to round result. Default: 4
    # ===== Returns 
    # mean size of stored profiles
    def get_profiles_mean_size(round_digits: 4)
        sizes = self.get_profiles_sizes
        return sizes.sum.fdiv(@profiles.length).round(round_digits)
    end


    # Calculates profiles sizes and returns size assigned to percentile given
    # ===== Parameters
    # +perc+:: percentile to be returned
    # +increasing_sort+:: flag to indicate if sizes order must be increasing. Default: false
    # ===== Returns 
    # values assigned to percentile asked
    def get_profile_length_at_percentile(perc=50, increasing_sort: false)
        prof_lengths = self.get_profiles_sizes.sort
        prof_lengths.reverse! if !increasing_sort
        n_profiles = prof_lengths.length 
        percentile_index = ((perc * (n_profiles - 1)).fdiv(100) - 0.5).round # Take length which not overpass percentile selected
        percentile_index = 0 if percentile_index < 0 # Special case (caused by literal calc)
        return prof_lengths[percentile_index]
    end


    # Translate a given profile to terms names
    # ===== Parameters
    # +prof+:: array of terms to be translated
    # ===== Returns 
    # array of translated terms. Can include nils if some IDs are not allowed
    def profile_names(prof)
        return prof.map{|term| self.translate_id(term)}
    end


    # Trnaslates a bunch of profiles to it sets of term names
    # ===== Parameters
    # +profs+:: array of profiles
    # +asArray+:: flag to indicate if results must be returned as: true => an array of tuples [ProfID, ArrayOdNames] or ; false => hashs of translations
    # ===== Returns 
    # translated profiles
    def translate_profiles_ids(profs = [], asArray: true)
        profs2proc = {}
        if profs.empty?
            profs2proc = @profiles 
        else
            profs.each_with_index{|terms, index| profs2proc[index] = terms} if profs.kind_of?(Array)
        end
        profs_names = {}
        profs2proc.each{|id, terms| profs_names[id] = self.profile_names(terms)}
        return asArray ? profs_names.values : profs_names
    end


    # Includes as "observed_terms" all terms included into stored profiles
    # ===== Parameters
    # +reset+:: if true, reset observed freqs alreeady stored befor re-calculate
    def add_observed_terms_from_profiles(reset: false)
        @meta.each{|term, freqs| freqs[:observed_freq] = -1} if reset
        @profiles.each{|id, terms| self.add_observed_terms(terms: terms)}
    end

    

    # Get a term frequency
    # ===== Parameters
    # +term+:: term to be checked
    # +type+:: type of frequency to be returned. Allowed: [:struct_freq, :observed_freq]
    # ===== Returns 
    # frequency of term given or nil if term is not allowed
    def get_frequency(term, type: :struct_freq)
        queryFreq = @meta[term]
        return queryFreq.nil? ? nil : queryFreq[type]        
    end


    # Geys structural frequency of a term given
    # ===== Parameters
    # +term+:: to be checked
    # ===== Returns 
    # structural frequency of given term or nil if term is not allowed
    def get_structural_frequency(term)
        return self.get_frequency(term, type: :struct_freq)
    end


    # Gets observed frequency of a term given
    # ===== Parameters
    # +term+:: to be checked
    # ===== Returns 
    # observed frequency of given term or nil if term is not allowed
    def get_observed_frequency(term)
        return self.get_frequency(term, type: :observed_freq)
    end


    # Calculates frequencies of stored profiles terms
    # ===== Parameters
    # +ratio+:: if true, frequencies will be returned as ratios between 0 and 1.
    # +asArray+:: used to transform returned structure format from hash of Term-Frequency to an array of tuples [Term, Frequency]
    # +translate+:: if true, term IDs will be translated to 
    # ===== Returns 
    # stored profiles terms frequencies
    def get_profiles_terms_frequency(ratio: true, asArray: true, translate: true)
        freqs = Hash.new(0)
        @profiles.each do |id, terms|
            terms.each{|term| freqs[term] += 1}
        end
        if translate
            translated_freqs = {}
            freqs.each do |term, freq| 
                tr = self.translate_id(term)
                translated_freqs[tr] = freq if !tr.nil?
            end
            freqs = translated_freqs
        end
        n_profiles = @profiles.length
        freqs.transform_values!{|freq| freq.fdiv(n_profiles)} if ratio
        if asArray
            freqs = freqs.to_a
            freqs.sort!{|h1, h2| h2[1] <=> h1[1]}
        end
        return freqs
    end    


    # Clean a given profile returning cleaned set of terms and removed ancestors term.
    # ===== Parameters
    # +prof+:: array of terms to be checked
    # ===== Returns 
    # two arrays, first is the cleaned profile and second is the removed elements array
    def remove_ancestors_from_profile(prof)
        ancestors = prof.map{|term| self.get_ancestors(term)}.flatten.uniq
        redundant = prof & ancestors
        return prof - redundant, redundant
    end


    # Remove alternative IDs if official ID is present. DOES NOT REMOVE synonyms or alternative IDs of the same official ID
    # ===== Parameters
    # +prof+:: array of terms to be checked
    # ===== Returns 
    # two arrays, first is the cleaned profile and second is the removed elements array
    def remove_alternatives_from_profile(prof)
        alternatives = prof.select{|term| @alternatives_index.include?(term)}
        redundant = alternatives.select{|alt_id| prof.include?(@alternatives_index[alt_id])}
        return prof - redundant, redundant
    end


    # Remove alternatives (if official term is present) and ancestors terms of a given profile 
    # ===== Parameters
    # +profile+:: profile to be cleaned
    # +remove_alternatives+:: if true, clenaed profiles will replace already stored profiles
    # ===== Returns 
    # cleaned profile
    def clean_profile(profile, remove_alternatives: true)
        warn('Estructure is circular, behaviour could not be which is expected') if @structureType == :circular
        terms_without_ancestors, _ = remove_ancestors_from_profile(profile)    
        terms_without_ancestors, _ = remove_alternatives_from_profile(terms_without_ancestors) if remove_alternatives
        return terms_without_ancestors
    end

    def clean_profile_hard(profile, options = {}) # NEED TEST # maybe see if obsoletes have an alt id to recover them in some cases
        profile, _ = check_ids(profile)
        profile = profile.select{|t| !is_obsolete?(t)}
        if !options[:term_filter].nil?
            profile.select! {|term| get_ancestors(term).include?(options[:term_filter])}
        end 
        profile = clean_profile(profile.uniq)
        return profile
    end

    # Remove terms from a given profile using hierarchical info and scores set given  
    # ===== Parameters
    # +profile+:: profile to be cleaned
    # +scores+:: hash with terms by keys and numerical values (scores)
    # +byMax+:: if true, maximum scored term will be keeped, if false, minimum will be keeped
    # +remove_without_score+:: if true, terms without score will be removed. Default: true
    # ===== Returns 
    # cleaned profile
    def clean_profile_by_score(profile, scores, byMax: true, remove_without_score: true)
        scores = scores.sort_by{|term,score| score}.to_h
        keep = profile.map do |term|
            if scores.include?(term)
                parentals = [self.get_ancestors(term), self.get_descendants(term)].flatten
                targetable = parentals.select{|parent| profile.include?(parent)}
                if targetable.empty? 
                    term
                else
                    targetable << term
                    targets = scores.select{|term,score| targetable.include?(term)}.to_h
                    byMax ? targets.keys.last : targets.keys.first
                end
            elsif remove_without_score
                nil
            else
                term
            end
        end
        return keep.compact.uniq
    end


    # Remove alternatives (if official term is present) and ancestors terms of stored profiles 
    # ===== Parameters
    # +store+:: if true, clenaed profiles will replace already stored profiles
    # +remove_alternatives+:: if true, clenaed profiles will replace already stored profiles
    # ===== Returns 
    # a hash with cleaned profiles
    def clean_profiles(store: false, remove_alternatives: true)
        cleaned_profiles = {}
        @profiles.each{ |id, terms| cleaned_profiles[id] = self.clean_profile(terms, remove_alternatives: remove_alternatives)}
        @profiles = cleaned_profiles if store
        return cleaned_profiles
    end


    # Calculates number of ancestors present (redundant) in each profile stored
    # ===== Returns 
    # array of parentals for each profile
    def parentals_per_profile
        cleaned_profiles = self.clean_profiles(remove_alternatives: false)
        parentals = @profiles.map{ |id, terms| terms.length - cleaned_profiles[id].length}
        return parentals
    end


    def get_profile_redundancy()
      profile_sizes = self.get_profiles_sizes
      parental_terms_per_profile = self.parentals_per_profile# clean_profiles
      parental_terms_per_profile = parental_terms_per_profile.map{|item| item[0]}
      profile_sizes, parental_terms_per_profile = profile_sizes.zip(parental_terms_per_profile).sort_by{|i| i.first}.reverse.transpose
      return profile_sizes, parental_terms_per_profile
    end

    def compute_term_list_and_childs()
      suggested_childs = {}
      total_terms = 0
      terms_with_more_specific_childs = 0
      @profiles.each do |id, terms|
        total_terms += terms.length
        more_specific_childs = self.get_childs_table(terms, true)
        terms_with_more_specific_childs += more_specific_childs.select{|profile| !profile.last.empty?}.length #Exclude phenotypes with no childs
        suggested_childs[id] = more_specific_childs  
      end
      return suggested_childs, terms_with_more_specific_childs.fdiv(total_terms)
    end

    #  Calculates mean IC of a given profile
    # ===== Parameters
    # +prof+:: profile to be checked
    # +ic_type+:: ic_type to be used
    # +zhou_k+:: special coeficient for Zhou IC method
    # ===== Returns 
    # mean IC for a given profile
    def get_profile_mean_IC(prof, ic_type: :resnik, zhou_k: 0.5)
        return prof.map{|term| self.get_IC(term, type: ic_type, zhou_k: zhou_k)}.sum.fdiv(prof.length)
    end    


    # Calculates resnik ontology, and resnik observed mean ICs for all profiles stored
    # ===== Returns 
    # two hashes with Profiles and IC calculated for resnik and observed resnik respectively
    def get_profiles_resnik_dual_ICs(struct: :resnik, observ: :resnik_observed)
        struct_ics = {}
        observ_ics = {}
        @profiles.each do |id, terms|
            struct_ics[id] = self.get_profile_mean_IC(terms, ic_type: struct)
            observ_ics[id] = self.get_profile_mean_IC(terms, ic_type: observ)
        end
        return struct_ics, observ_ics
    end    


    # Calculates ontology structural levels for all ontology terms
    # ===== Parameters
    # +calc_paths+:: calculates term paths if it's not already calculated
    # +shortest_path+:: if true, level is calculated with shortest path, largest path will be used in other cases
    def calc_term_levels(calc_paths: false, shortest_path: true) # NEED TEST
        self.calc_term_paths if @term_paths.empty? && calc_paths
        if !@term_paths.empty?
            byTerm = {}
            byValue = {}
            @term_paths.each do |term, info|
                level = shortest_path ? info[:shortest_path] : info[:largest_path]
                level = level.nil? ? -1 : level.round(0)
                byTerm[term] = level
                add2hash(byValue, level, term)
            end
            @dicts[:level] = {byTerm: byValue, byValue: byTerm} # Note: in this case, value has multiplicity and term is unique value
            @max_freqs[:max_depth] = byValue.keys.max # Update maximum depth
        end
    end

    # Find paths of a term following it ancestors and stores all possible paths for it and it's parentals.
    # Also calculates paths metadata and stores into @term_paths
    def calc_term_paths # NEED TEST
        visited_terms = {} # PEDRO: To keep track of visited data, hash accesions are fast than array includes. I don't understant why use this variable instead of check @term_paths to see if the data is calculated
        @term_paths = {}
        if [:hierarchical, :sparse].include? @structureType
            each(only_main = false) do |term|
                if !visited_terms.include?(term)
                    # PEDRO: This code is very similar to expand_path method, but cannot be replaced by it (test fail). We must work to use this method here
                    path_attr = @term_paths[term]
                    if path_attr.nil?
                        path_attr = {total_paths: 0, largest_path: 0, shortest_path: 0, paths: []} # create new path data
                        @term_paths[term] = path_attr #save path data container
                    end
                    parentals = @dicts[:is_a][:byTerm][term]
                    if parentals.nil?
                        path_attr[:paths] << [term]
                    else
                        parentals.each do |direct_parental|
                            self.expand_path(direct_parental)
                            new_paths = @term_paths[direct_parental][:paths]
                            path_attr[:paths].concat(new_paths.map{|path| path.clone.unshift(term)})
                        end
                    end                    
                    @ancestors_index[term].each{|anc| visited_terms[anc] = true} if @ancestors_index.include?(term)
                    visited_terms[term] = true
                end
                # Update metadata
                path_attr = @term_paths[term]
                path_attr[:total_paths] = path_attr[:paths].length
                paths_sizes = path_attr[:paths].map{|path| path.length}
                path_attr[:largest_path] = paths_sizes.max
                path_attr[:shortest_path] = paths_sizes.min
            end
        else
            warn('Ontology structure must be hierarchical or sparse to calculate term levels. Aborting paths calculation')
        end
    end


    # Recursive function whic finds paths of a term following it ancestors and stores all possible paths for it and it's parentals
    # ===== Parameters
    # +curr_term+:: current visited term
    # +visited_terms+:: already expanded terms
    def expand_path(curr_term) # NEED TEST
        if !@term_paths.include?(curr_term)
            path_attr = {total_paths: 0, largest_path: 0, shortest_path: 0, paths: []}
            @term_paths[curr_term] = path_attr
            direct_parentals = @dicts[:is_a][:byTerm][curr_term]
            if direct_parentals.nil? # No parents :: End of recurrence
                path_attr[:paths] << [curr_term]
            else # Expand and concat
                direct_parentals.each do |ancestor|
                    path_attr_parental = @term_paths[ancestor]
                    if path_attr_parental.nil? # Calculate new paths
                        self.expand_path(ancestor) 
                        new_paths = @term_paths[ancestor][:paths]
                    else # Use direct_parental paths already calculated 
                        new_paths = path_attr_parental[:paths] 
                    end
                    path_attr[:paths].concat(new_paths.map{|path| path.clone.unshift(curr_term)})
                end
            end
        end
    end


    # Gets ontology levels calculated
    # ===== Returns 
    # ontology levels calculated
    def get_ontology_levels # NEED TEST
        return @dicts[:level][:byTerm].clone # By term, in this case, is Key::Level, Value::Terms
    end


    # Gets ontology level of a specific term
    # ===== Returns 
    # Term level
    def get_term_level(term) # NEED TEST
        return @dicts[:level][:byValue][term]
    end

    def get_terms_levels(terms) # NEED TEST
        termsAndLevels = []
        terms.each do |term|
            termsAndLevels << [term, get_term_level(term)]
        end
        return termsAndLevels
    end


    # nil, term not found, [] term exists but not has parents
    def get_parental_path(term, which_path = :shortest_path, level = 0) # NEED TEST
        path = nil
        path_attr = @term_paths[term]
        if !path_attr.nil?
            path_length = path_attr[which_path]
            all_paths = path_attr[:paths]
            if all_paths.empty?
                path = []
            else
                path = all_paths.select{|pt| pt.length == path_length}.first.clone
                if level > 0 # we want the term and his ascendants until a specific level
                    n_parents = path_length - level 
                    path = path[0..n_parents]
                end
                path.shift # Discard the term itself
            end
        end
        return path
    end

    # Return ontology levels from profile terms
    # ===== Returns 
    # hash of term levels (Key: level; Value: array of term IDs)
    def get_ontology_levels_from_profiles(uniq = true) # TODO: remove uniq and check dependencies
        profiles_terms = @profiles.values.flatten
        profiles_terms.uniq! if uniq
        term_freqs_byProfile = Hash.new(0)
        profiles_terms.each do |term|
            term_freqs_byProfile[term] += 1 
        end
        levels_filtered = {}
        terms_levels = @dicts[:level][:byValue]
        term_freqs_byProfile.each do |term, count|
            level = terms_levels[term]
            term_repeat = Array.new(count, term)
            query = levels_filtered[level]
            if query.nil?
                levels_filtered[level] = term_repeat
            else
                query.concat(term_repeat)
            end
        end
        return levels_filtered
    end

    def get_profile_ontology_distribution_tables # NEED TEST, Generalize nomenclature
      cohort_ontology_levels = get_ontology_levels_from_profiles(uniq=false)
      uniq_cohort_ontology_levels = get_ontology_levels_from_profiles
      hpo_ontology_levels = get_ontology_levels
      total_ontology_terms = hpo_ontology_levels.values.flatten.length
      total_cohort_terms = cohort_ontology_levels.values.flatten.length
      total_uniq_cohort_terms = uniq_cohort_ontology_levels.values.flatten.length

      ontology_levels = []
      distribution_percentage = []
      hpo_ontology_levels.each do |level, terms|
        cohort_terms = cohort_ontology_levels[level]
        uniq_cohort_terms = uniq_cohort_ontology_levels[level]
        if cohort_terms.nil? || uniq_cohort_terms.nil?
          num = 0
          u_num = 0
        else
          num = cohort_terms.length
          u_num = uniq_cohort_terms.length
        end
        ontology_levels << [level, terms.length, num]
        distribution_percentage << [
          level,
          (terms.length.fdiv(total_ontology_terms)*100).round(3),
          (num.fdiv(total_cohort_terms)*100).round(3),
          (u_num.fdiv(total_uniq_cohort_terms)*100).round(3)
        ]
      end
      ontology_levels.sort! { |x,y| x.first <=> y.first }
      distribution_percentage.sort! { |x,y| x.first <=> y.first }
      return ontology_levels, distribution_percentage
    end

    def get_dataset_specifity_index(mode) # NEED TEST
        ontology_levels, distribution_percentage = get_profile_ontology_distribution_tables
        if mode == 'uniq'
            observed_distribution = 3
        elsif mode == 'weigthed'
            observed_distribution = 2
        end
        max_terms = distribution_percentage.map{|row| row[1]}.max
        maxL = nil 
        distribution_percentage.each do |level_info|
            maxL = level_info.first if level_info[1] == max_terms
        end
        diffL = distribution_percentage.map{|l| [l[0], l[observed_distribution] - l[1]]}
        diffL.select!{|dL| dL.last > 0}
        lowSection = diffL.select{|dL| dL.first <= maxL}
        highSection = diffL.select{|dL| dL.first > maxL}
        dsi = nil
        if highSection.empty?
            dsi = 0
        else
            hss = get_weigthed_level_contribution(highSection, maxL, ontology_levels.length - maxL)
            lss = get_weigthed_level_contribution(lowSection, maxL, maxL)
            dsi = hss.fdiv(lss)
        end
        return dsi
    end

    def get_weigthed_level_contribution(section, maxL, nLevels) # NEED TEST
        accumulated_weigthed_diffL = 0
        section.each do |level, diff|
            weightL = maxL - level 
            if weightL >= 0
                weightL += 1
            else
                weightL = weightL.abs
            end
            accumulated_weigthed_diffL += diff * weightL
        end
        weigthed_contribution = accumulated_weigthed_diffL.fdiv(nLevels)
        return weigthed_contribution
    end


    # For each term in profiles add the ids in the items term-id dictionary 
    def get_items_from_profiles # NEED TEST
        @profiles.each do |id, terms|
            terms.each {|term| add2hash(@items, term, id) }
        end
    end

    def get_profiles_from_items # NEED TEST
        new_profiles = {}
        @items.each do |term, ids|
            ids.each{|id| add2hash(new_profiles, id, term) }
        end
        @profiles = new_profiles        
    end

    # Get related profiles to a given term
    # ===== Parameters
    # +term+:: to be checked
    # ===== Returns 
    # profiles which contains given term
    def get_items_from_term(term)
        return @items[term]
    end

    # Gets metainfo table from a set of terms
    # ===== Parameters
    # +terms+:: IDs to be expanded
    # +filter_alternatives+:: flag to be used in get_descendants method
    # ===== Returns 
    # an array with triplets [TermID, TermName, DescendantsNames]
    def get_childs_table(terms, filter_alternatives = false)
        expanded_terms = []
        terms.each do |t|
            expanded_terms << [[t, translate_id(t)], get_descendants(t, filter_alternatives).map{|child| [child, translate_id(child)]}]
        end
        return expanded_terms
    end


    # Store specific relations hash given into ITEMS structure
    # ===== Parameters
    # +relations+:: hash to be stored
    # +remove_old_relations+:: substitute ITEMS structure instead of merge new relations
    # +expand+:: if true, already stored keys will be updated with the unique union of both sets
    def load_item_relations_to_terms(relations, remove_old_relations = false, expand = false)
        @items = {} if remove_old_relations        
        relations.each do |term, items| 
            if !term_exist?(term)
                warn('Some terms specified are not stored into this ontology. These not correct terms will be stored too')
                break
            end
        end
        if expand
            @items = self.concatItems(@items, relations)
        else
            @items.merge!(relations)
        end
    end 

    # Internal function to concat two elements.
    # ===== Parameters
    # +itemA+:: item to be concatenated
    # +itemB+:: item to be concatenated
    # ===== Returns
    # Concatenated objects
    def concatItems(itemA,itemB) # NEED TEST, CHECK WITH PSZ THIS METHOD
        # A is Array :: RETURN ARRAY
            # A_array : B_array
            # A_array : B_hash => NOT ALLOWED
            # A_array : B_single => NOT ALLOWED
        # A is Hash :: RETURN HASH
            # A_hash : B_array => NOT ALLOWED
            # A_hash : B_hash
            # A_hash : B_single => NOT ALLOWED
        # A is single element => RETURN ARRAY
            # A_single : B_array
            # A_single : B_hash => NOT ALLOWED
            # A_single : B_single
        concatenated = nil
        if itemA.kind_of?(Array) && itemB.kind_of?(Array)
            concatenated = itemA | itemB
        elsif itemA.kind_of?(Hash) && itemB.kind_of?(Hash)
            concatenated = itemA.merge(itemB) do |k, oldV, newV| 
                self.concatItems(oldV,newV)
            end
        elsif itemB.kind_of?(Array)
            concatenated = ([itemA] + itemB).uniq
        elsif ![Array, Hash].include?(itemB.class)
            concatenated = [itemA,itemB].uniq
        end
        return concatenated
    end      


    # Assign a dictionary already calculated as a items set.
    # ===== Parameters
    # +dictID+:: dictionary ID to be stored (:byTerm will be used)
    def set_items_from_dict(dictID, remove_old_relations = false) # NEED TEST
        @items = {} if remove_old_relations
        query = @dicts[dictID]
        if !query.nil?
            @items.merge(query[:byTerm])
        else
            warn('Specified ID is not calculated. Dict will not be added as a items set')
        end
    end

    def expand_profile_with_parents(profile) # NEED TEST
        new_terms = []
        profile.each do |term|
            new_terms = new_terms | get_ancestors(term)
        end
        return new_terms | profile
    end

    def expand_profiles(meth, unwanted_terms: [], calc_metadata: true, ontology: nil, minimum_childs: 1, clean_profiles: true) # NEED TEST
        if meth == 'parental'
            @profiles.each do |id, terms|
                @profiles[id] = expand_profile_with_parents(terms) - unwanted_terms
            end
            get_items_from_profiles if calc_metadata
        elsif meth == 'propagate'
            get_items_from_profiles
            expand_items_to_parentals(ontology: ontology, minimum_childs: minimum_childs, clean_profiles: clean_profiles)
            get_profiles_from_items
        end
        add_observed_terms_from_profiles(reset: true)        
    end 

    # This method computes childs similarity and impute items to it parentals. To do that Item keys must be this ontology allowed terms.
    # Similarity will be calculated by text extact similarity unless an ontology object will be provided. In this case, MICAs will be used
    # ===== Parameters
    # +ontology+:: (Optional) ontology object which items given belongs
    # +minimum_childs+:: minimum of childs needed to infer relations to parental. Default: 2
    # +clean_profiles+:: if true, clena_profiles ontology method will be used over inferred profiles. Only if an ontology object is provided
    # ===== Returns
    # void and update items object
    def expand_items_to_parentals(ontology: nil, minimum_childs: 2, clean_profiles: true)
        targetKeys = expand_profile_with_parents(@items.keys)
        terms_per_level = list_terms_per_level(targetKeys)        
        terms_per_level = terms_per_level.to_a.sort{|l1, l2| l1.first <=> l2.first} # Obtain sorted levels 
        terms_per_level.pop # Leaves are not expandable

        terms_per_level.reverse_each do |lvl, terms| # Expand from leaves to roots
            terms.each do |term|
                childs = self.get_descendants(term, true).select{|t| @items.include?(t)} # Get child with items
                next if childs.length < minimum_childs
                propagated_item_count = Hash.new(0)                
                if ontology.nil? # Count how many times is presented an item in childs
                    childs.each do |child| 
                        @items[child].each{|i| propagated_item_count[i] += 1}
                    end 
                else # Count take into account similarity between terms in other ontology. Not pretty clear the full logic
                    while childs.length > 1 
                        curr_term = childs.shift
                        childs.each do |child|
                            maxmica_counts = Hash.new(0)
                            curr_items = @items[curr_term]
                            child_items = @items[child]
                            curr_items.each do |item|
                                maxmica = ontology.get_maxmica_term2profile(item, child_items)
                                maxmica_counts[maxmica.first] += 1
                            end
                            child_items.each do |item|
                                maxmica = ontology.get_maxmica_term2profile(item, curr_items)
                                maxmica_counts[maxmica.first] += 1
                            end
                            maxmica_counts.each{|t,freq| propagated_item_count[t] += freq if freq >= 2} #TODO: Maybe need Division by 2 due to the calculation of mica two times  but test fails.
                        end
                    end
                end
                propagated_items = propagated_item_count.select{|k,v| v >= minimum_childs}.keys
                if propagated_items.length > 0
                    query = @items[term]
                    if query.nil?
                        @items[term] = propagated_items
                    else 
                        terms = @items[term] | propagated_items
                        terms = ontology.clean_profile(terms) if clean_profiles && !ontology.nil?
                        @items[term] = terms
                    end
                end
            end
        end
    end

    def get_maxmica_term2profile(ref_term, profile)
        micas = profile.map{|term| get_MICA(ref_term, term)}
        maxmica = micas.first
        micas.each{|mica| maxmica = mica if mica.last > maxmica.last}
        return maxmica
    end

    # Return direct ancestors/descendants of a given term
    # ===== Parameters
    # +term+:: which are requested
    # +relation+:: can be :ancestor or :descendant 
    # +remove_alternatives+:: if true, alternatives will be removed
    # ===== Returns
    # Direct ancestors/descendants of given term or nil if any error occurs
    def get_direct_related(term, relation, remove_alternatives: false) # NEED TEST
        if @dicts[:is_a].nil?
            warn("Hierarchy dictionary is not already calculated. Returning nil")
            return nil
        end 
        target = nil
        case relation
            when :ancestor
                target = :byTerm
            when :descendant
                target = :byValue
            else
                warn('Relation type not allowed. Returning nil')
        end
        return nil if target.nil? 
        query = @dicts[:is_a][target][term]
        return nil if query.nil?
        query, _ = remove_alternatives_from_profile(query) if remove_alternatives
        return query
    end


    # Return direct ancestors of a given term
    # ===== Parameters
    # +term+:: which ancestors are requested
    # +remove_alternatives+:: if true, alternatives will be removed
    # ===== Returns
    # Direct ancestors of given term or nil if any error occurs
    def get_direct_ancentors(term, remove_alternatives: false)
        return self.get_direct_related(term, :ancestor, remove_alternatives: remove_alternatives)
    end

    # Return direct descendants of a given term
    # ===== Parameters
    # +term+:: which descendants are requested
    # +remove_alternatives+:: if true, alternatives will be removed
    # ===== Returns
    # Direct descendants of given term or nil if any error occurs
    def get_direct_descendants(term, remove_alternatives: false)
        return self.get_direct_related(term, :descendant, remove_alternatives: remove_alternatives)        
    end

    def each(att = false, only_main = true) # NEED TEST
        warn('terms empty') if @terms.empty?
        @terms.each do |id, tags|            
            next if only_main && (@alternatives_index.include?(id) || @obsoletes.include?(id))
            if att
               yield(id, tags)
            else
               yield(id)
            end
        end
    end

    def get_root # NEED TEST
        roots = []
        each do |term|
            roots << term if @ancestors_index[term].nil? 
        end
        return roots
    end

    def list_term_attributes # NEED TEST
        terms = []
        each do |code|
            terms << [code, translate_id(code), get_term_level(code)]
        end
        return terms
    end

#============================================================================
#============================================================================

    # NO IDEA WHAT THIS DOES. DON'T USE THIS METHODS IS NOT CHECKED
    # ===== Parameters
    # ++::
    # ===== Returns
    # ...
     def compute_relations_to_items(external_item_list, total_items, mode, thresold) # NEED TEST, check with PSZ how to maintain these methods
        terms_levels = list_terms_per_level_from_items 
        connect_familiars!(terms_levels)
        item_list_with_transf_parental = get_item_list_parental(terms_levels)
        results = []
        if mode == :elim 
            results = compute_relations_elim(terms_levels, external_item_list, total_items, thresold, item_list_with_transf_parental)
        elsif mode == :weight
            results = compute_relations_weight(terms_levels, external_item_list, total_items, item_list_with_transf_parental)
        end
        return results
    end

    def get_item_list_parental(terms_levels)
        transfered_list = {}
        parent_dict = @dicts[:is_a][:byTerm]
        levels = terms_levels.keys.sort
        while levels.length > 1
            level = levels.pop
            terms_levels[level].each do |term|
                parents = parent_dict[term]
                if parents.nil?
                    next
                elsif parents.length == 1
                    parent = parents.first
                else
                    parent = (parents | terms_levels[level - 1]).first
                end
                term_it = @items[term]
                parent_it = @items[parent]
                curr_it = transfered_list[term]
                parent_all_items = merge_groups([term_it, parent_it, curr_it])
                transfered_list[parent] = parent_all_items if !parent_all_items.empty?
                term_all_items = merge_groups([term_it, curr_it])
                transfered_list[term] = term_all_items if !term_all_items.empty?
            end
        end
        terms_levels[levels.first].each do |term| # Rescue lower level terms that not have children so they cannot receive items
            transfered_list[term] = @items[term] if transfered_list[term].nil?
        end
        return transfered_list
    end

    def merge_groups(groups)
        return groups.compact.inject([ ]){|it, a| it | a}
    end

    def list_terms_per_level_from_items
        return list_terms_per_level(@items.keys)
    end

    def list_terms_per_level(terms)
        terms_levels = {}
        terms.each do |term| 
          level = self.get_term_level(term)
          add2hash(terms_levels, level, term)
        end
        return terms_levels
    end

    def connect_familiars!(terms_levels)
        levels = terms_levels.keys.sort
        while levels.length > 1 # Process when current level has a parental level
            level = levels.pop
            parental_level = level - 1
            parental_terms = terms_levels[parental_level]
            if parental_terms.nil? # The queried parent level not exists but there is a parental level above of the non existant
                parental_terms = [] # Initialize required parental level
                terms_levels[parental_level] = parental_terms
                levels << parental_level
            end
            terms_levels[level].each do |term|
                path_info = @term_paths[term]
                shortest_path_length = path_info[:shortest_path] 
                path = path_info[:paths].select{|p| p.length == shortest_path_length}.first
                parental = path[1] # the first elements is the term itself
                parental_terms << parental if !parental_terms.include?(parental)
            end
        end
    end

    def compute_relations_elim(terms_levels, external_item_list, total_items, thresold, item_list)
        results = []
        penalized_terms = {}
        levels = terms_levels.keys.sort
        levels.reverse_each do |level|
            terms_levels[level].each do |term|
                associated_items = item_list[term]
                items_to_remove = penalized_terms[term]
                items_to_remove = [] if items_to_remove.nil?
                pval = get_fisher_exact_test(
                    external_item_list - items_to_remove, 
                    associated_items - items_to_remove, 
                    #((associated_items | external_item_list) - items_to_remove).length
                    total_items
                    )
                if pval <= thresold
                    parents = get_ancestors(term) # Save the items for each parent term to remove them later in the fisher test
                    parents.each do |prnt|
                        query = penalized_terms[prnt]
                        if query.nil?
                            penalized_terms[prnt] = item_list[term].clone # We need a new array to store the following iterations
                        else
                            query.concat(item_list[term])
                        end
                    end
                end
                results << [term, pval]
            end
        end
        return results
    end

    def compute_relations_weight(terms_levels, external_item_list, total_items, item_list)
        pvals = {}
        item_weigths_per_term = Hash.new { |hash, key|  Hash.new(1) } #https://mensfeld.pl/2016/09/ruby-hash-default-value-be-cautious-when-you-use-it/
        levels = terms_levels.keys.sort
        levels.reverse_each do |level|
            terms_levels[level].each do |term|
                associated_items = item_list[term]
                #initialize observed items in item_weigths_per_term list
                add_items_to_weigthed_list(term, associated_items, item_weigths_per_term) if !associated_items.nil?
                children = @dicts[:is_a][:byValue][term]
                if children.nil?
                    children = []
                else
                    children = children.select{|ch| item_weigths_per_term[ch].length > 0} # Only use children with items associated to them OR transfered to them
                end
                computeTermSig(term, children, external_item_list, total_items, pvals, item_weigths_per_term)
            end
        end
        return pvals.to_a     
    end

    def add_items_to_weigthed_list(term, associated_items, weigthed_list)
        term_weigthing = weigthed_list[term]
        associated_items.each{|ai| term_weigthing[ai] = 1}
        weigthed_list[term] = term_weigthing
    end

    def computeTermSig(term, children, external_item_list, total_items, pvals, item_weigths_per_term)
        #puts term.to_s.red
        #puts @term_paths[term].inspect
        #puts @dicts[:is_a][:byValue][term].inspect.light_blue
        associated_items = item_weigths_per_term[term].keys
        pval = get_fisher_exact_test(external_item_list, associated_items, total_items, 
                                    'two_sided', item_weigths_per_term[term], true)
        pvals[term] = pval
        if children.length > 0
            rates = {}
            sig_child = 0
            children.each do |child|
                ratio = sigRatio(pvals[child], pval)
                rates[child] = ratio 
                sig_child += 1 if ratio >= 1
            end
            if sig_child == 0 # CASE 1
                children.each do |child|
                    current_ratio = rates[child]
                    query_child = item_weigths_per_term[child]
                    query_child.transform_values!{|weight| weight * current_ratio}
                    pvals[child] = get_fisher_exact_test(external_item_list, item_weigths_per_term[child].keys, total_items, 
                                      'two_sided', item_weigths_per_term[child], true)
                end
            else
                ancs = get_ancestors(term, filter_alternatives = true)
                ancs << term
                rates.each do |ch, ratio|# CASE 2
                    if ratio >= 1 # The child is better than parent
                        ancs.each do |anc|
                            query_anc = item_weigths_per_term[anc]
                            associated_items.each do |item|
                                query_anc[item] /= ratio # /= --> query_anc[item]/ratio
                            end
                        end
                    end
                end
                computeTermSig(term, children - rates.keys, external_item_list, total_items, pvals, item_weigths_per_term)
            end
        end
    end

    def sigRatio(pvalA, pvalB)
        return Math.log(pvalA)/Math.log(pvalB)
    end

    #============================================================================
    # END of methods involved with compute_relations_to_items
    #============================================================================


    def profile_stats # NEED TEST
      stats = Hash.new(0)
      data = get_profiles_sizes
      stats[:average] = data.sum().fdiv(data.size)
      sum_devs = data.sum{|element| (element - stats[:avg]) ** 2}
      stats[:variance] = sum_devs.fdiv(data.size)
      stats[:standardDeviation] = stats[:variance] ** 0.5
      stats[:max] = data.max
      stats[:min] = data.min

      stats[:count] = data.size
      data.each do |value|
        stats[:countNonZero] += 1 if value != 0
      end

      stats[:q1] = data.get_quantiles(0.25)
      stats[:median] = data.get_quantiles(0.5)
      stats[:q3] = data.get_quantiles(0.75)
      return stats

    end

#============================================================================
#============================================================================

    ############################################
    # SPECIAL METHODS
    #############################################
    def ==(other)
        self.terms == other.terms &&
        self.ancestors_index == other.ancestors_index &&
        self.alternatives_index == other.alternatives_index &&
        self.obsoletes_index == other.obsoletes_index &&
        self.structureType == other.structureType &&
        self.ics == other.ics &&
        self.meta == other.meta &&
        self.dicts == other.dicts &&
        self.profiles == other.profiles &&
        (self.items.keys - other.items.keys).empty? &&
        self.items == other.items &&
        self.term_paths == other.term_paths &&
        self.max_freqs == other.max_freqs
    end


    def clone
        copy = Ontology.new
        copy.terms = self.terms.clone
        copy.ancestors_index = self.ancestors_index.clone
        copy.descendants_index = self.descendants_index.clone
        copy.alternatives_index = self.alternatives_index.clone
        copy.obsoletes_index = self.obsoletes_index.clone
        copy.structureType = self.structureType.clone
        copy.ics = self.ics.clone
        copy.meta = self.meta.clone
        copy.dicts = self.dicts.clone
        copy.profiles = self.profiles.clone
        copy.items = self.items.clone
        copy.term_paths = self.term_paths.clone
        copy.max_freqs = self.max_freqs.clone
        return copy
    end

    private

    def add2hash(hash, key, val)
        query = hash[key]
        if query.nil?
            hash[key] = [val]
        else
            query << val
        end
    end    

    def add2nestHash(h, key1, key2, val)
        query1 = h[key1]
        if query1.nil?
            h[key1] = {key2 => val} 
        else
            query1[key2] = val
        end
    end
end
