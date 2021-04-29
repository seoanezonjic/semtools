require 'json'
require 'colorize'


class Ontology
    #########################################################
    # AUTHOR NOTES
    #########################################################

    # 1 - Store @profiles as @stanzas[:instances]
    # 2 - Items values (not keys) are imported as strings, not as symbols (maybe add a flag which indicates if values are, or not, symbols?) 


    #############################################
    # FIELDS
    #############################################
    # Handled class variables
    # => @@basic_tags :: hash with main OBO structure tags
    # => @@allowed_calcs :: hash with allowed ICs and similaritites calcs
    # => @@symbolizable_ids :: tags which can be symbolized
    # => @@tags_with_trailing_modifiers :: tags which can include extra info after specific text modifiers
    #
    # Handled object variables
    # => @header :: file header (if is available)
    # => @stanzas :: OBO stanzas {:terms,:typedefs,:instances}
    # => @ancestors_index :: hash of ancestors per each term handled with any structure relationships
    # => @descendants_index :: hash of descendants per each term handled with any structure relationships
    # => @alternatives_index :: has of alternative IDs (include alt_id and obsoletes)
    # => @obsoletes_index :: hash of obsoletes and it's new ids
    # => @special_tags :: set of special tags to be expanded (:is_a, :obsolete, :alt_id)
    # => @structureType :: type of ontology structure depending on ancestors relationship. Allowed: {atomic, sparse, circular, hierarchical}
    # => @ics :: already calculated ICs for handled terms and IC types
    # => @meta :: meta_information about handled terms like [ancestors, descendants, struct_freq, observed_freq]
    # => @max_freqs :: maximum freqs found for structural and observed freqs
    # => @dicts :: bidirectional dictionaries with three levels <key|value>: 1º) <tag|hash2>; 2º) <(:byTerm/:byValue)|hash3>; 3º) dictionary <k|v>
    # => @profiles :: set of terms assigned to an ID
    # => @profilesDict :: set of profile IDs assigned to a term
    # => @items :: hash with items relations to terms
    # => @removable_terms :: array of terms to not be considered
    # => @term_paths :: metainfo about parental paths of each term

    @@basic_tags = {ancestors: [:is_a], obsolete: :is_obsolete, alternative: [:replaced_by,:consider,:alt_id]}
    @@allowed_calcs = {ics: [:resnik, :resnik_observed, :seco, :zhou, :sanchez], sims: [:resnik, :lin, :jiang_conrath]}
    @@symbolizable_ids = [:id, :alt_id, :replaced_by, :consider]
    @@tags_with_trailing_modifiers = [:is_a, :union_of, :disjoint_from, :relationship, :subsetdef, :synonymtypedef, :property_value]
    @@multivalue_tags = [:alt_id, :is_a, :subset, :synonym, :xref, :intersection_of, :union_of, :disjoint_from, :relationship, :replaced_by, :consider, :subsetdef, :synonymtypedef, :property_value, :remark]
    @@symbolizable_ids.concat(@@tags_with_trailing_modifiers)
    
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
    def initialize(file: nil, load_file: false, removable_terms: [], build: true, file_format: nil)
        # Initialize object variables
        @header = nil
        @stanzas = {terms: {}, typedefs: {}, instances: {}}
        @ancestors_index = {}
        @descendants_index = {}
        @alternatives_index = {}
        @obsoletes_index = {}
        @structureType = nil
        @ics = Hash[@@allowed_calcs[:ics].map{|ictype| [ictype, {}]}]
        @meta = {}
        @special_tags = @@basic_tags.clone
        @max_freqs = {:struct_freq => -1.0, :observed_freq => -1.0, :max_depth => -1.0}
        @dicts = {}
        @profiles = {}
        @profilesDict = {}
        @items = {}
        @removable_terms = []
        @term_paths = {}
        add_removable_terms(removable_terms) if !removable_terms.empty?
        load_file = true unless file.nil? # This should remove load_file argument, keep it for old scripts
        # Load if proceeds
        if load_file
            fformat = file_format
            fformat = File.extname(file) if fformat.nil? && !file.nil?
            if fformat == :obo || fformat == ".obo"
                load(file, build: build)
            elsif fformat == :json || fformat == ".json"
                self.read(file, build: build)
            elsif !fformat.nil?
                warn 'Format not allowed. Loading process will not be performed'
            end
        end
    end


    #############################################
    # CLASS METHODS
    #############################################

    # Expand a (starting) term using a specific tag and return all extended terms into an array and
    # the relationship structuture observed (hierarchical or circular). If circular structure is
    # foumd, extended array will be an unique vector without starting term (no loops).
    # +Note+: we extremly recomend use get_related_ids_by_tag function instead of it (directly)
    # ===== Parameters
    # +start+:: term where start to expand
    # +terms+:: set to be used to expand
    # +target_tag+:: tag used to expand
    # +eexpansion+:: already expanded info
    # +split_info_char+:: special regex used to split info (if it is necessary)
    # +split_info_indx+:: special index to take splitted info (if it is necessary)
    # +alt_ids+:: set of alternative IDs
    # ===== Returns 
    # A vector with the observed structure (string) and the array with extended terms.
    def self.get_related_ids(start_id, terms, target_tag, related_ids = {}, alt_ids = {})
        # Take start_id term available info and already accumulated info
        current_associations = related_ids[start_id]
        current_associations = [] if current_associations.nil? 
        return [:no_term,[]] if terms[start_id].nil?
        id_relations = terms[start_id][target_tag]
        return [:source,[]] if id_relations.nil?

        # Prepare auxiliar variables
        struct = :hierarchical

        # Study direct extensions
        id_relations = id_relations.clone
        while id_relations.length > 0
            id = id_relations.shift
            id = alt_ids[id].first if alt_ids.include?(id) # NOTE: if you want to persist current ID instead source ID, re-implement this
            
            # Handle
            if current_associations.include?(id) # Check if already have been included into this expansion
                struct = :circular 
            else
                current_associations << id 
                if related_ids.include?(id) # Check if current already has been expanded
                    current_associations = current_associations | related_ids[id]
                    if current_associations.include?(start_id) # Check circular case
                        struct = :circular
                        [id, start_id].each{|repeated| current_associations.delete(repeated)}
                    end    
                else # Expand
                    related_ids[start_id] = current_associations
                    structExp, current_related_ids = self.get_related_ids(id, terms, target_tag, related_ids, alt_ids) # Expand current
                    current_associations = current_associations | current_related_ids
                    struct = :circular if structExp == :circular # Check struct                
                    if current_associations.include?(start_id) # Check circular case
                        struct = :circular
                        current_associations.delete(start_id)
                    end
                end
            end
        end
        related_ids[start_id] = current_associations

        return struct, current_associations
    end


    # Expand terms using a specific tag and return all extended terms into an array and
    # the relationship structuture observed (hierarchical or circular). If circular structure is
    # foumd, extended array will be an unique vector without starting term (no loops) 
    # ===== Parameters
    # +terms+:: set to be used to expand
    # +target_tag+:: tag used to expand
    # +split_info_char+:: special regex used to split info (if it is necessary)
    # +split_info_indx+:: special index to take splitted info (if it is necessary)
    # +alt_ids+:: set of alternative IDs
    # +obsoletes+:: integer with the number of obsolete IDs. used to calculate structure type.
    # ===== Returns 
    # A vector with the observed structure (string) and the hash with extended terms
    def self.get_related_ids_by_tag(terms:,target_tag:, alt_ids: {}, obsoletes: 0)
        # Define structure type
        structType = :hierarchical
        related_ids = {}
        terms.each do |id, tags|
            # Check if target tag is defined
            if !tags[target_tag].nil?
                # Obtain related terms
                set_structure, _ = self.get_related_ids(id, terms, target_tag, related_ids, alt_ids)
                # Check structure            
                structType = :circular if set_structure == :circular
            end
        end

        # Check special case
        structType = :atomic if related_ids.length <= 0
        structType = :sparse if related_ids.length > 0 && ((terms.length - related_ids.length - obsoletes) >= 2)
        # Return type and hash with related_ids
        return structType, related_ids
    end


    # Class method to transform string with <tag : info> into hash structure
    # ===== Parameters
    # +attributes+:: array tuples with info to be transformed into hash format
    # ===== Returns 
    # Attributes stored into hash structure
    def self.info2hash(attributes, split_char = " ! ", selected_field = 0)
        # Load info
        info_hash = {}
        # Only TERMS multivalue tags (future add Typedefs and Instance)
        # multivalue_tags = [:alt_id, :is_a, :subset, :synonym, :xref, :intersection_of, :union_of, :disjoint_from, :relationship, :replaced_by, :consider]
        attributes.each do |tag, value|
            # Check
            raise EncodingError, 'Info element incorrect format' if (tag.nil?) || (value.nil?)
            # Prepare
            tag = tag.lstrip.to_sym
            value.lstrip!
            value = value.split(split_char)[selected_field].to_sym if @@tags_with_trailing_modifiers.include?(tag)
            
            # Store
            query = info_hash[tag]
            if !query.nil? # Tag already exists
                if !query.kind_of?(Array) # Check that tag is multivalue
                    raise('Attempt to concatenate plain text with another. The tag is not declared as multivalue. [' + tag.to_s + '](' + query + ')')
                else
                    query << value    # Add new value to tag
                end
            else # New entry
                if @@multivalue_tags.include?(tag)
                    info_hash[tag] = [value]
                else
                    info_hash[tag] = value
                end
            end
        end
        self.symbolize_ids(info_hash)
        return info_hash
    end


    # Class method to load an OBO format file (based on OBO 1.4 format). Specially focused on load
    # the Header, the Terms, the Typedefs and the Instances.
    # ===== Parameters
    # +file+:: OBO file to be loaded
    # ===== Returns 
    # Hash with FILE, HEADER and STANZAS info
    def self.load_obo(file) #TODO: Send to obo_parser class
        raise("File is not defined") if file.nil?
        # Data variables
        header = ''
        stanzas = {terms: {}, typedefs: {}, instances: {}}
        # Auxiliar variables
        infoType = 'Header'
        currInfo = []
        stanzas_flags = %w[[Term] [Typedef] [Instance]]
        # Read file
        File.open(file).each do |line|
            line.chomp!
            next if line.empty?
            fields = line.split(':', 2)
            # Check if new instance is found
            if stanzas_flags.include?(line)
                header = self.process_entity(header, infoType, stanzas, currInfo)
                # Update info variables
                currInfo = []
                infoType = line.gsub!(/[\[\]]/, '')
                next
            end
            # Concat info
            currInfo << fields  
        end
        # Store last loaded info
        header = self.process_entity(header, infoType, stanzas, currInfo) if !currInfo.empty?

        # Prepare to return
        finfo = {:file => file, :name => File.basename(file, File.extname(file))}
        return finfo, header, stanzas
    end


    # Handle OBO loaded info and stores it into correct container and format
    # ===== Parameters
    # +header+:: container
    # +infoType+:: current ontology item type detected
    # +stanzas+:: container
    # +currInfo+:: info to be stored
    # ===== Returns 
    # header newly/already stored
    def self.process_entity(header, infoType, stanzas, currInfo)
        info = self.info2hash(currInfo)
        # Store current info
        if infoType.eql?('Header')
            header = info
        else
            id = info[:id]
            case infoType
                when 'Term'
                    stanzas[:terms][id] = info
                when 'Typedef'
                    stanzas[:typedefs][id] = info
                when 'Instance'
                    stanzas[:instances][id] = info
            end
        end
        return header
    end


    # Symboliza all values into hashs using symbolizable tags as keys
    # ===== Parameters
    # +item_hash+:: hash to be checked
    def self.symbolize_ids(item_hash)
        @@symbolizable_ids.each do |tag|
            query = item_hash[tag] 
            if !query.nil?
                if query.kind_of?(Array)
                    query.map!{|item| item.to_sym}
                else
                    item_hash[tag] = query.to_sym if !query.nil?
                end
            end
        end
    end


    #
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
        ontology.stanzas[:terms] = ontology.stanzas[:terms].select{|id,v| remove_up ? descendants.include?(id) : !descendants.include?(id)}
        ontology.ics = Hash[@@allowed_calcs[:ics].map{|ictype| [ictype, {}]}]
        ontology.max_freqs = {:struct_freq => -1.0, :observed_freq => -1.0, :max_depth => -1.0}
        ontology.dicts = {}
        ontology.removable_terms = []
        ontology.term_paths = {}
        # Recalculate metadata
        ontology.build_index
        ontology.add_observed_terms_from_profiles
        # Finish
        return ontology
    end



    #############################################
    # GENERAL METHODS
    #############################################

    # Include removable terms to current removable terms list
    # ===== Parameters
    # +terms+:: terms array to be concatenated
    def add_removable_terms(terms)
        terms = terms.map{|term| term.to_sym}
        @removable_terms.concat(terms)
    end


    # Include removable terms to current removable terms list loading new
    # terms from a one column plain text file
    # ===== Parameters
    # +file+:: to be loaded 
    def add_removable_terms_from_file(file)
        File.open(excluded_codes_file).each do |line|
            line.chomp!
            @removable_terms << line.to_sym
        end
    end

    
    # Increase observed frequency for a specific term
    # ===== Parameters
    # +term+:: term which frequency is going to be increased
    # +increas+:: frequency rate to be increased. Default = 1
    # ===== Return
    # true if process ends without errors, false in other cases
    def add_observed_term(term:,increase: 1.0)
        # Check
        raise ArgumentError, "Term given is NIL" if term.nil?
        return false unless @stanzas[:terms].include?(term)
        return false if @removable_terms.include?(term)
        if @alternatives_index.include?(term)
            alt_id = @alternatives_index[term]
            @meta[alt_id] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:observed_freq => 0.0} if @meta[alt_id].nil?
            @meta[term] = @meta[alt_id]             
        end
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
        # Check
        raise ArgumentError, 'Terms array given is NIL' if terms.nil?
        raise ArgumentError, 'Terms given is not an array' if !terms.is_a? Array
        # Add observations
        if transform_to_sym
            checks = terms.map{|id| self.add_observed_term(term: id.to_sym,increase: increase)}
        else
            checks = terms.map{|id| self.add_observed_term(term: id,increase: increase)}
        end
        return checks
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
    def compare(termsA, termsB, sim_type: :resnik, ic_type: :resnik, bidirectional: true)
        # Check
        raise ArgumentError, "Terms sets given are NIL" if termsA.nil? | termsB.nil?
        raise ArgumentError, "Set given is empty. Aborting similarity calc" if termsA.empty? | termsB.empty?
        micasA = []
        # Compare A -> B
        termsA.each do |tA|
            micas = []
            termsB.each do |tB| 
               value = self.get_similarity(tA, tB, type: sim_type, ic_type: ic_type)
               micas << value if !value.nil? && !value
            end            
            if !micas.empty
                micasA << micas.max  > 0 # Obtain maximum value
            else
                micasA << 0
            end
        end
        means_sim = micasA.inject{ |sum, el| sum + el }.to_f / micasA.size
        # Compare B -> A
        if bidirectional
            means_simA = means_sim * micasA.size
            means_simB = self.compare(termsB, termsA, sim_type: sim_type, ic_type: ic_type, bidirectional: false) * termsB.size
            means_sim = (means_simA + means_simB) / (termsA.size + termsB.size)
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
        profiles_ids = @profiles.keys
        if external_profiles.nil?
            comp_ids = profiles_ids
            comp_profiles = @profiles
            main_ids = comp_ids
            main_profiles = comp_profiles
        else
            comp_ids = external_profiles.keys
            comp_profiles = external_profiles
            main_ids = profiles_ids
            main_profiles = @profiles
        end
        # Compare
        while !main_ids.empty?
            curr_id = main_ids.shift
            current_profile = main_profiles[curr_id]
            comp_ids.each do |id|
                profile = comp_profiles[id]
                value = compare(current_profile, profile, sim_type: sim_type, ic_type: ic_type, bidirectional: bidirectional)
                query = profiles_similarity[curr_id]
                if query.nil?
                  profiles_similarity[curr_id] = {id => value}
                else
                  query[id] = value
                end
            end    
        end
        return profiles_similarity
    end


    # Expand alternative IDs arround all already stored terms
    # ===== Parameters
    # +alt_tag+:: tag used to expand alternative IDs
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def get_index_alternatives(alt_tag: @@basic_tags[:alternative].last)
        # Check input
        raise('stanzas terms empty')  if @stanzas[:terms].empty?
        # Take all alternative IDs
        alt_ids2add = {}
        @stanzas[:terms].each do |id, tags|
            if id == tags[:id] # Avoid simulated alternative terms
                # id = tags[:id] # Take always real ID in case of alternative terms simulted
                alt_ids = tags[alt_tag]
                if !alt_ids.nil?
                    alt_ids = alt_ids - @removable_terms - [id]
                    # Update info
                    alt_ids.each do |alt_term|
                        @alternatives_index[alt_term] = id
                        alt_ids2add[alt_term] = @stanzas[:terms][id] if !@stanzas[:terms].include?(alt_term)
                        @ancestors_index[alt_term] = @ancestors_index[id] if !@ancestors_index[id].nil?
                    end
                end
            end
        end
        @stanzas[:terms].merge!(alt_ids2add)
    end


    # Executes basic expansions of tags (alternatives, obsoletes and parentals) with default values
    # ===== Returns 
    # true if eprocess ends without errors and false in other cases
    def build_index()
        self.get_index_obsoletes
        self.get_index_alternatives
        self.get_index_child_parent_relations
            @alternatives_index.map{|k,v| @alternatives_index[k] = self.extract_id(v)}
            ## @alternatives_index.map {|k,v| @alternatives_index[k] = self.stanzas[:terms][v][:id] if k == v} unless self.stanzas[:terms].empty?
            @alternatives_index.compact!
            @obsoletes_index.map{|k,v| @obsoletes_index[k] = self.extract_id(v)}
            @obsoletes_index.compact!
            @ancestors_index.map{|k,v| @ancestors_index[k] = v.map{|t| self.extract_id(t)}.compact}
            @ancestors_index.compact!
            @descendants_index.map{|k,v| @descendants_index[k] = v.map{|t| self.extract_id(t)}.compact}
            @descendants_index.compact!
        self.get_index_frequencies
        self.calc_dictionary(:name)
        self.calc_dictionary(:synonym, select_regex: /\"(.*)\"/)
        self.calc_term_levels(calc_paths: true)
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
            @stanzas[:terms].each do |id, tags|            
                if @alternatives_index.include?(id)
                    alt_id = @alternatives_index[id]
                    query = @meta[alt_id] # Check if exist
                    if query.nil?
                        query = {ancestors: 0.0, descendants: 0.0, struct_freq: 0.0, observed_freq: 0.0}
                        @meta[alt_id] = query 
                    end 
                    @meta[id] = query
                    # Note: alternative terms do not increase structural frequencies
                else # Official term
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


    # Expand obsoletes set and link info to their alternative IDs
    # ===== Parameters
    # +obs_tags+:: tags to be used to find obsoletes
    # +alt_tags+:: tags to find alternative IDs (if are available)
    # +reset_obsoletes+:: flag to indicate if obsoletes set must be reset. Default: true
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def get_index_obsoletes(obs_tag: @@basic_tags[:obsolete], alt_tags: @@basic_tags[:alternative])
        if @stanzas[:terms].empty?
            warn('stanzas terms empty')
        else
            # Check obsoletes
            @stanzas[:terms].each do |id, term_tags|
                next if term_tags.nil?
                next if self.is_alternative?(id)
                query = term_tags[obs_tag]
                if !query.nil? && query == 'true' # Obsolete tag presence 
                    next if !@obsoletes_index[id].nil? # Already stored
                    # Check if alternative value is available
                    alt_ids = alt_tags.map{|alt| term_tags[alt]}.compact
                    if !alt_ids.empty?
                        alt_id = alt_ids.first.first #FIRST tag, FIRST id 
                        # Store
                        @alternatives_index[id] = alt_id
                        @obsoletes_index[id] = alt_id
                    end
                end
            end
        end
    end


    # Expand parentals set and link all info to their alternative IDs. Also launch frequencies process
    # ===== Parameters
    # +tag+:: tag used to expand parentals
    # +split_info_char+:: special regex used to split info (if it is necessary)
    # +split_info_indx+:: special index to take splitted info (if it is necessary)
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def get_index_child_parent_relations(tag: @@basic_tags[:ancestors][0])
        # Check
        if @stanzas[:terms].nil?
            warn('stanzas terms empty')
        else
            # Expand
            structType, parentals = self.class.get_related_ids_by_tag(terms: @stanzas[:terms],
                                                            target_tag: tag,
                                                            alt_ids: @alternatives_index,
                                                            obsoletes: @obsoletes_index.length)
            # Check
            raise('Error expanding parentals')  if (structType.nil?) || parentals.nil?
            # Prepare ancestors structure
            anc = {}
            des = {}
            parentals.each do |id, parents|
                parents = parents - @removable_terms
                anc[id] = parents
                parents.each do |anc_id| # Add descendants
                    if !des.include?(anc_id)
                        des[anc_id] = [id]
                    else 
                        des[anc_id] << id
                    end
                end
            end
            # Store alternatives
            @alternatives_index.each do |id,alt|
                anc[id] = anc[alt] if anc.include?(alt)
                des[id] = des[alt] if des.include?(alt)
            end
            # Check structure
            if ![:atomic,:sparse].include? structType
                structType = structType == :circular ? :circular : :hierarchical
            end
            # Store
            @ancestors_index = anc
            @descendants_index = des
            @structureType = structType
        end
        # Finish        
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
        # Check 
        raise ArgumentError, "IC type specified (#{type}) is not allowed" if !@@allowed_calcs[:ics].include?(type)
        # Check if it's already calculated
        return @ics[type][term] if (@ics[type].include? term) && !force
        # Calculate
        ic = - 1
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
                ic = -Math.log10(@meta[term][:struct_freq].fdiv(@max_freqs[:struct_freq]))
            when :resnik_observed 
                # -log(Freq(x) / Max_Freq)
                ic = -Math.log10(@meta[term][:observed_freq].fdiv(@max_freqs[:observed_freq]))
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
                ic = 1 - Math.log10(@meta[term][:struct_freq]).fdiv(Math.log10(@stanzas[:terms].length - @alternatives_index.length))
                if :zhou # New Model of Semantic Similarity Measuring in Wordnet                
                    # k*(IC_Seco(x)) + (1-k)*(log(depth(x))/log(max_depth))
                    @ics[:seco][term] = ic # Special store
                    ic = zhou_k * ic + (1.0 - zhou_k) * (Math.log10(@meta[term][:descendants]).fdiv(Math.log10(@max_freqs[:max_depth])))
                end
            when :sanchez # Semantic similarity estimation in the biomedical domain: An ontology-basedinformation-theoretic perspective
                ic = -Math.log10((@meta[term][:descendants].fdiv(@meta[term][:ancestors]) + 1.0).fdiv(@max_freqs[:max_depth] + 1.0))
            # Knappe
        end            
        @ics[type][term] = ic
        return ic
    end


    # Calculates and return resnik ICs (by ontology and observed frequency) for observed terms
    # ===== Returns 
    # two hashes with resnik and resnik_observed ICs for observed terms
    def get_observed_ics_by_onto_and_freq
        # Chech there are observed terms
        if @profiles.empty?
            resnik = {}
            resnik_observed = {}
        else
            # Calc ICs for all terms
            observed_terms = @profiles.values.flatten.uniq
            observed_terms.each{ |term| get_IC(term)}
            observed_terms.each{ |term| get_IC(term, type: :resnik_observed)}
            resnik = @ics[:resnik].select{|k,v| observed_terms.include?(k)}
            resnik_observed = @ics[:resnik_observed].select{|k,v| observed_terms.include?(k)}
        end
        return resnik.clone, resnik_observed.clone
    end


    # Find the IC of the Most Index Content shared Ancestor (MICA) of two given terms
    # ===== Parameters
    # +termA+:: term to be cheked
    # +termB+:: term to be checked
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the IC of the MICA(termA,termB)
    def get_ICMICA(termA, termB, ic_type = :resnik)
        mica = self.get_MICA(termA, termB, ic_type)
        return mica.first.nil? ? nil : mica.last
    end


    # Find the Most Index Content shared Ancestor (MICA) of two given terms
    # ===== Parameters
    # +termA+:: term to be cheked
    # +termB+:: term to be checked
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the MICA(termA,termB) and it's IC
    def get_MICA(termA, termB, ic_type = :resnik)
        termA = @alternatives_index[termA] if @alternatives_index.include?(termA)
        termB = @alternatives_index[termB] if @alternatives_index.include?(termB)
        mica = [nil,-1.0]
        # Special case
        if termA.eql?(termB)
            ic = self.get_IC(termA, type: ic_type)
            mica = [termA, ic]
        else    
            # Obtain ancestors (include itselfs too)
            anc_A = self.get_ancestors(termA) 
            anc_B = self.get_ancestors(termB)

            if !(anc_A.empty? && anc_B.empty?)
                anc_A << termA
                anc_B << termB
                # Find shared ancestors
                shared_ancestors = anc_A & anc_B
                # Find MICA
                if shared_ancestors.length > 0
                    shared_ancestors.each do |anc|
                        ic = self.get_IC(anc, type: ic_type)
                        # Check
                        mica = [anc,ic] if ic > mica[1]
                    end
                end
            end
        end
        return mica
    end


    # Calculate similarity between two given terms
    # ===== Parameters
    # +termsA+:: to be compared
    # +termsB+:: to be compared
    # +type+:: similitude formula to be used
    # +ic_type+:: IC formula to be used
    # ===== Returns 
    # the similarity between both sets or false if frequencies are not available yet
    def get_similarity(termA, termB, type: :resnik, ic_type: :resnik)
        # Check
        raise ArgumentError, "SIM type specified (#{type}) is not allowed" if !@@allowed_calcs[:sims].include?(type)
        sim = nil
        # Launch comparissons
        sim_res = get_ICMICA(termA, termB, ic_type)
        if !sim_res.nil?
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


    # Method used to load information stored into an OBO file and store it into this object.
    # If a file is specified by input parameter, current @file value is updated
    # ===== Parameters
    # +file+:: optional file to update object stored file
    def load(file, build: true)
        _, header, stanzas = self.class.load_obo(file)
        @header = header
        @stanzas = stanzas
        self.remove_removable()
        # @removable_terms.each{|removableID| @stanzas[:terms].delete(removableID)} if !@removable_terms.empty? # Remove if proceed
        self.build_index() if build
    end

    # 
    def remove_removable()
        @removable_terms.each{|removableID| @stanzas[:terms].delete(removableID)} if !@removable_terms.empty? # Remove if proceed
    end


    # Exports an OBO_Handler object in json format
    # ===== Parameters
    # +file+:: where info will be stored
    def write(file)
        # Take object stored info
        obj_info = {header: @header,
                    stanzas: @stanzas,
                    ancestors_index: @ancestors_index,
                    descendants_index: @descendants_index,
                    alternatives_index: @alternatives_index,
                    obsoletes_index: @obsoletes_index,
                    structureType: @structureType,
                    ics: @ics,
                    meta: @meta,
                    special_tags: @special_tags,
                    max_freqs: @max_freqs,
                    dicts: @dicts,
                    profiles: @profiles,
                    profilesDict: @profilesDict,
                    items: @items,
                    removable_terms: @removable_terms,
                    term_paths: @term_paths}
        # Convert to JSON format & write
        File.open(file, "w") { |f| f.write obj_info.to_json }
    end


    def is_number? string
          true if Float(string) rescue false
    end


    # Read a JSON file with an OBO_Handler object stored
    # ===== Parameters
    # +file+:: with object info
    # +file+:: if true, calculate indexes. Default: true
    # ===== Return
    # OBO_Handler internal fields 
    def read(file, build: true)
        # Read file
        jsonFile = File.open(file)
        jsonInfo = JSON.parse(jsonFile.read, :symbolize_names => true)
        # Pre-process (Symbolize some hashs values)
        if !jsonInfo[:header].nil?
            aux = jsonInfo[:header].map do |entry,info|
                if info.kind_of?(Array) && @@symbolizable_ids.include?(entry) 
                    [entry,info.map{|item| item.to_sym}]
                else
                    [entry,info]
                end
            end
            jsonInfo[:header] = aux.to_h
        end
        jsonInfo[:stanzas][:terms].map{|id,info| self.class.symbolize_ids(info)} # STANZAS
        jsonInfo[:stanzas][:typedefs].map{|id,info| self.class.symbolize_ids(info)}
        jsonInfo[:stanzas][:instances].map{|id,info| self.class.symbolize_ids(info)}
        # Optional
        jsonInfo[:alternatives_index] = jsonInfo[:alternatives_index].map{|id,value| [id, value.to_sym]}.to_h unless jsonInfo[:alternatives_index].nil?
        jsonInfo[:ancestors_index].map {|id,family_arr| family_arr.map!{|item| item.to_sym}} unless jsonInfo[:ancestors_index].nil?
        jsonInfo[:descendants_index].map {|id,family_arr| family_arr.map!{|item| item.to_sym}} unless jsonInfo[:descendants_index].nil?
        jsonInfo[:obsoletes_index] = jsonInfo[:obsoletes_index].map{|id,value| [id, value.to_sym]}.to_h unless jsonInfo[:obsoletes_index].nil?
        jsonInfo[:dicts] = jsonInfo[:dicts].each do |flag, dictionaries|
            next if dictionaries.nil?
            # Special case: byTerm
            dictionaries[:byTerm] = dictionaries[:byTerm].map do |term, value| 
                if !term.to_s.scan(/\A[-+]?[0-9]*\.?[0-9]+\Z/).empty?  # Numeric dictionary
                    [term.to_s.to_i, value.map{|term| term.to_sym}]
                elsif value.is_a? Numeric # Numeric dictionary
                    [term.to_sym, value]
                elsif value.kind_of?(Array) && flag == :is_a
                    [term.to_sym, value.map{|v| v.to_sym}]
                else
                    [term.to_sym, value]
                end
            end
            dictionaries[:byTerm] = dictionaries[:byTerm].to_h
            # By value
            dictionaries[:byValue] = dictionaries[:byValue].map do |value, term| 
                if value.is_a? Numeric # Numeric dictionary
                    [value, term.to_sym]
                elsif term.is_a? Numeric # Numeric dictionary
                    [value.to_s.to_sym, term]
                elsif flag == :is_a
                    [value.to_sym, term.map{|v| v.to_sym}]
                elsif term.kind_of?(Array)
                    [value.to_sym, term.map{|t| t.to_sym}]
                else
                    [value.to_s, term.to_sym]
                end
            end
            dictionaries[:byValue] = dictionaries[:byValue].to_h
        end 
        if !jsonInfo[:profiles].nil?
            jsonInfo[:profiles].map{|id,terms| terms.map!{|term| term.to_sym}}
            jsonInfo[:profiles].keys.map{|id| jsonInfo[:profiles][id.to_s.to_i] = jsonInfo[:profiles].delete(id) if self.is_number?(id.to_s)}
        end
        jsonInfo[:profilesDict].map{|term,ids| ids.map!{|id| id.to_sym if !id.is_a?(Numeric)}} unless jsonInfo[:profilesDict].nil?
        jsonInfo[:removable_terms] = jsonInfo[:removable_terms].map{|term| term.to_sym} unless jsonInfo[:removable_terms].nil?
        jsonInfo[:special_tags] = jsonInfo[:special_tags].each do |k, v|
            next if v.nil?
            if v.kind_of?(Array)
                jsonInfo[:special_tags][k] = v.map{|tag| tag.to_sym}
            else
                jsonInfo[:special_tags][k] = v.to_sym
            end
        end
        jsonInfo[:items].each{|k,v| jsonInfo[:items][k] = v.map{|item| item.to_sym}} unless jsonInfo[:items].nil?
        jsonInfo[:term_paths].each{|term,info| jsonInfo[:term_paths][term][:paths] = info[:paths].map{|path| path.map{|t| t.to_sym}}} unless jsonInfo[:term_paths].nil?
        
        # Store info
        @header = jsonInfo[:header]
        @stanzas = jsonInfo[:stanzas]
        @ancestors_index = jsonInfo[:ancestors_index]
        @descendants_index = jsonInfo[:descendants_index]
        @alternatives_index = jsonInfo[:alternatives_index]
        @obsoletes_index = jsonInfo[:obsoletes_index]
        jsonInfo[:structureType] = jsonInfo[:structureType].to_sym unless jsonInfo[:structureType].nil?
        @structureType = jsonInfo[:structureType]
        @ics = jsonInfo[:ics]
        @meta = jsonInfo[:meta]
        @special_tags = jsonInfo[:special_tags]
        @max_freqs = jsonInfo[:max_freqs]
        @dicts = jsonInfo[:dicts]
        @profiles = jsonInfo[:profiles]
        @profilesDict = jsonInfo[:profilesDict]
        @items = jsonInfo[:items]
        @removable_terms = jsonInfo[:removable_terms]
        @term_paths = jsonInfo[:term_paths]

        self.build_index() if build
    end


    # Check if a given ID is stored as term into this object
    # ===== Parameters
    # +id+:: to be checked 
    # ===== Return
    # True if term is allowed or false in other cases
    def exists? id
        return stanzas[:terms].include?(id)
    end


    # This method assumes that a text given contains an allowed ID. And will try to obtain it splitting it
    # ===== Parameters
    # +text+:: to be checked 
    # ===== Return
    # The correct ID if it can be found or nil in other cases
    def extract_id(text, splitBy: ' ')
        if self.exists?(text)
            return text
        else
            splittedText = text.to_s.split(splitBy).first.to_sym
            return self.exists?(splittedText) ? splittedText : nil
        end
    end


    # Generate a bidirectinal dictionary set using a specific tag and terms stanzas set
    # This functions stores calculated dictionary into @dicts field.
    # This functions stores first value for multivalue tags
    # This function does not handle synonyms for byValue dictionaries
    # ===== Parameters
    # +tag+:: to be used to calculate dictionary
    # +select_regex+:: gives a regfex that can be used to modify value to be stored
    # +substitute_alternatives+:: flag used to indicate if alternatives must, or not, be replaced by it official ID
    # +store_tag+:: flag used to store dictionary. If nil, mandatory tag given will be used
    # +multiterm+:: if true, byValue will allows multi-term linkage (array)
    # +self_type_references+:: if true, program assumes that refrences will be between Ontology terms, and it term IDs will be checked
    # ===== Return
    # void. And stores calcualted bidirectional dictonary into dictionaries main container
    def calc_dictionary(tag, select_regex: nil, substitute_alternatives: true, store_tag: nil, multiterm: false, self_type_references: false)
        tag = tag.to_sym
        store_tag = tag if store_tag.nil?
        if @stanzas[:terms].empty?
            warn('Terms are not already loaded. Aborting dictionary calc') 
        else
            byTerm = {}
            byValue = {}
            # Calc per term
            @stanzas[:terms].each do |term, tags|
                referenceTerm = term
                if @alternatives_index.include?(term) && substitute_alternatives # Special case
                    referenceTerm = @alternatives_index[term] if !@obsoletes_index.include?(@alternatives_index[term])
                end
                queryTag = tags[tag]
                if !queryTag.nil?
                    # Pre-process
                    if !select_regex.nil?
                        if queryTag.kind_of?(Array)
                            queryTag = queryTag.map{|value| value.scan(select_regex).first}
                            queryTag.flatten!
                        else
                            queryTag = queryTag.scan(select_regex).first
                        end
                        queryTag.compact!
                    end
                    if queryTag.kind_of?(Array) # Store
                        if !queryTag.empty?
                            if byTerm.include?(referenceTerm)
                                byTerm[referenceTerm] = (byTerm[referenceTerm] + queryTag).uniq
                            else
                                byTerm[referenceTerm] = queryTag
                            end
                            if multiterm
                                queryTag.each do |value|
                                    byValue[value] = [] if byValue[value].nil? 
                                    byValue[value] << referenceTerm
                                end                                
                            else
                                queryTag.each{|value| byValue[value] = referenceTerm}
                            end
                        end
                    else
                        if byTerm.include?(referenceTerm)
                            byTerm[referenceTerm] = (byTerm[referenceTerm] + [queryTag]).uniq
                        else
                            byTerm[referenceTerm] = [queryTag]
                        end
                        if multiterm
                            byValue[queryTag] = [] if byValue[queryTag].nil?
                            byValue[queryTag] << referenceTerm
                        else
                            byValue[queryTag] = referenceTerm
                        end
                    end
                end
            end
            
            # Check self-references
            if self_type_references
                byTerm.map do |term, references|
                    corrected_references = references.map do |t|
                        checked = self.extract_id(t)
                        if checked.nil?
                            t
                        else
                            byValue[checked] = byValue.delete(t) if checked != t && byValue[checked].nil? # Update in byValue
                            checked
                        end
                    end
                    byTerm[term] = corrected_references.uniq
                end
            end

            # Check order
            byTerm.map do |term,values|
                if self.exists?(term)
                    referenceValue = @stanzas[:terms][term][tag]
                    if !referenceValue.nil?
                        if !select_regex.nil?
                            if referenceValue.kind_of?(Array)
                                referenceValue = referenceValue.map{|value| value.scan(select_regex).first}
                                referenceValue.flatten!
                            else
                                referenceValue = referenceValue.scan(select_regex).first
                            end
                            referenceValue.compact!
                        end
                        if self_type_references
                            if referenceValue.kind_of?(Array)
                                aux = referenceValue.map{|t| self.extract_id(t)}
                            else
                                aux = self.extract_id(referenceValue)
                            end
                            aux.compact! unless aux.nil?
                            referenceValue = aux unless aux.nil?
                        end
                        referenceValue = [referenceValue] if !referenceValue.kind_of?(Array)
                        byTerm[term] = referenceValue + (values - referenceValue)
                    end
                end
            end

            # Store
            @dicts[store_tag] = {byTerm: byTerm, byValue: byValue}
        end
    end


    # Calculates :is_a dictionary without alternatives substitution
    def calc_ancestors_dictionary
        self.calc_dictionary(:is_a, substitute_alternatives: false, self_type_references: true, multiterm: true)
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
    def get_main_id(id)
        return nil if !@stanzas[:terms].include? id
        new_id = id
        mainID = @alternatives_index[id]
        new_id = mainID if !mainID.nil? & !@obsoletes_index.include?(mainID)
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
            if @stanzas[:terms].include? id
                if substitute
                    checked_codes << self.get_main_id(id)
                else
                    checked_codes << id
                end
            else
                rejected_codes << id
            end
        end
        return checked_codes, rejected_codes
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
            warn('Given terms contains erroneus IDs. These IDs will be removed')
        end
        if id.is_a? Numeric
            @profiles[id] = correct_terms              
        else
            @profiles[id.to_sym] = correct_terms  
        end
    end    


    # Method used to store a pull of profiles
    # ===== Parameters
    # +profiles+:: array/hash of profiles to be stored. If it's an array, numerical IDs will be assigned starting at 1 
    # +calc_metadata+:: if true, launch calc_profiles_dictionary process
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
            self.calc_profiles_dictionary
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
        return sizes.inject(0){|sum, n| sum + n}.fdiv(@profiles.length).round(round_digits)
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
        profs = @profiles if profs.empty?
        profs = profs.each_with_index.map{|terms, index| [index, terms]}.to_h if profs.kind_of?(Array)
        profs_names = profs.map{|id, terms| [id, self.profile_names(terms)]}.to_h
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
    # +literal+:: if true, literal terms will be used to calculate frequencies instead translate alternative terms
    # +asArray+:: used to transform returned structure format from hash of Term-Frequency to an array of tuples [Term, Frequency]
    # +translate+:: if true, term IDs will be translated to 
    # ===== Returns 
    # stored profiles terms frequencies
    def get_profiles_terms_frequency(ratio: true, literal: true, asArray: true, translate: true)
        n_profiles = @profiles.length
        if literal
            freqs = {}
            @profiles.each do |id, terms|
                terms.each do |literalTerm|
                    if freqs.include?(literalTerm)
                        freqs[literalTerm] += 1
                    else
                        freqs[literalTerm] = 1
                    end
                end
            end
            if (ratio || translate)
                aux_keys = freqs.keys
                aux_keys.each do |term| 
                    freqs[term] = freqs[term].fdiv(n_profiles) if ratio
                    if translate
                        tr = self.translate_id(term)
                        freqs[tr] = freqs.delete(term) if !tr.nil?
                    end
                end
            end
            if asArray
                freqs = freqs.map{|term, freq| [term, freq]}
                freqs.sort!{|h1, h2| h2[1] <=> h1[1]}
            end
        else # Freqs translating alternatives
            freqs = @meta.select{|id, freqs| freqs[:observed_freq] > 0}.map{|id, freqs| [id, ratio ? freqs[:observed_freq].fdiv(n_profiles) : freqs[:observed_freq]]}
            freqs = freqs.to_h if !asArray
            if translate
                freqs = freqs.map do |term, freq|
                    tr = self.translate_id(term)
                    tr.nil? ? [term, freq] : [tr, freq]
                end
            end
            if asArray
                freqs = freqs.map{|term, freq| [term, freq]}
                freqs.sort!{|h1, h2| h2[1] <=> h1[1]}
            else
                freqs = freqs.to_h
            end
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
        redundant = prof.select{|term| ancestors.include?(term)}
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
        terms_without_ancestors, _ = self.remove_ancestors_from_profile(profile)
        if remove_alternatives
            terms_without_ancestors_and_alternatices, _ = self.remove_alternatives_from_profile(terms_without_ancestors)
        else
            terms_without_ancestors_and_alternatices = terms_without_ancestors
        end
        return terms_without_ancestors_and_alternatices
    end

    # Replace alternatives,  remove obsolete and ancestors terms of a given profile 
    # ===== Parameters
    # +profile+:: profile to be cleaned
    # ===== Returns 
    # cleaned profile
    def clean_profile_hard(profile)
        profile = profile.select{|t| !is_obsolete?(t)}
        profile = check_ids(profile).uniq
        profile = clean_profile(profile, true)
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


    #  Calculates mean IC of a given profile
    # ===== Parameters
    # +prof+:: profile to be checked
    # +ic_type+:: ic_type to be used
    # +zhou_k+:: special coeficient for Zhou IC method
    # ===== Returns 
    # mean IC for a given profile
    def get_profile_mean_IC(prof, ic_type: :resnik, zhou_k: 0.5)
        return prof.map{|term| self.get_IC(term, type: ic_type, zhou_k: zhou_k)}.inject(0){|sum,x| sum + x}.fdiv(prof.length)
    end    


    # Calculates resnik ontology, and resnik observed mean ICs for all profiles stored
    # ===== Returns 
    # two hashes with Profiles and IC calculated for resnik and observed resnik respectively
    def get_profiles_resnik_dual_ICs
        struct_ics = {}
        observ_ics = {}
        @profiles.each do |id, terms|
            struct_ics[id] = self.get_profile_mean_IC(terms, ic_type: :resnik)
            observ_ics[id] = self.get_profile_mean_IC(terms, ic_type: :resnik_observed)
        end
        return struct_ics.clone, observ_ics.clone
    end    


    # Calculates ontology structural levels for all ontology terms
    # ===== Parameters
    # +calc_paths+:: calculates term paths if it's not already calculated
    # +shortest_path+:: if true, level is calculated with shortest path, largest path will be used in other cases
    def calc_term_levels(calc_paths: false, shortest_path: true)
        if @term_paths.empty?
            if calc_paths
                self.calc_term_paths
            else
                warn('Term paths are not already loaded. Aborting dictionary calc') 
            end
        end
        if !@term_paths.empty?
            byTerm = {}
            byValue = {}
            # Calc per term
            @term_paths.each do |term, info|
                level = shortest_path ? info[:shortest_path] : info[:largest_path]
                if level.nil?
                    level = -1
                else
                    level = level.round(0)
                end
                byTerm[term] = level
                queryLevels = byValue[level]
                if queryLevels.nil?
                    byValue[level] = [term]
                else
                    byValue[level] << term
                end
            end
            @dicts[:level] = {byTerm: byValue, byValue: byTerm} # Note: in this case, value has multiplicity and term is unique value
            # Update maximum depth
            @max_freqs[:max_depth] = byValue.keys.max
        end
    end


    # Check if a term given is marked as obsolete. If the term is an alternative to other id, is moved to @alternatives_index
    def is_obsolete? term
        return @obsoletes_index.include?(term)
    end

    # Check if a term given is marked as alternative
    def is_alternative? term
        return @alternatives_index.include?(term)
    end

    # Find paths of a term following it ancestors and stores all possible paths for it and it's parentals.
    # Also calculates paths metadata and stores into @term_paths
    def calc_term_paths(only_main_terms=false)
        self.calc_ancestors_dictionary if @dicts[:is_a].nil? # Calculate direct parentals dictionary if it's not already calculated
        visited_terms = {} # PEDRO: To keep track of visited data, hash accesions are fast than array includes. I don't understant why use this variable instead of check @term_paths to see if the data is calculated
        @term_paths = {}
        if [:hierarchical, :sparse].include? @structureType
            @stanzas[:terms].each do |term, t_attributes|
                if !only_main_terms && (self.is_obsolete?(term) || self.is_alternative?(term))  # Special case (obsoletes)
                    special_term = term
                    term = self.is_obsolete?(term) ? @obsoletes_index[term] : @alternatives_index[term]
                    @term_paths[term] = {total_paths: 0, largest_path: 0, shortest_path: 0, paths: []} if !@term_paths.include?(term)
                    @term_paths[special_term] = @term_paths[term]
                    visited_terms[special_term] = true
                end

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
    def expand_path(curr_term)
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
    def get_ontology_levels
        return @dicts[:level][:byTerm].clone # By term, in this case, is Key::Level, Value::Terms
    end


    # Gets ontology level of a specific term
    # ===== Returns 
    # Term level
    def get_term_level(term)
        return @dicts[:level][:byValue][term]
    end

    # nil, term not found, [] term exists but not has parents
    def get_parental_path(term, which_path = :shortest_path, level = 0)
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
        term_freqs_byProfile = {}
        profiles_terms.each do |term|
            query = term_freqs_byProfile[term]
            if query.nil?
                term_freqs_byProfile[term] = 1
            else
                term_freqs_byProfile[term] += 1
            end
        end
        levels_filtered = @dicts[:level][:byTerm].map{|level, terms| [level,terms.map{|t| profiles_terms.include?(t) ? Array.new(term_freqs_byProfile[t], t) : nil}.flatten.compact]}.select{|level, filteredTerms| !filteredTerms.empty?}.to_h
        return levels_filtered
    end


    # Calculate profiles dictionary with Key= Term; Value = Profiles
    def calc_profiles_dictionary
        if @profiles.empty?
            warn('Profiles are not already loaded. Aborting dictionary calc')
        else
            byTerm = {} # Key: Terms
            # byValue -- Key: Profile == @profiles
            @profiles.each do |id, terms|
                terms.each do |term|
                    if byTerm.include?(term)
                        byTerm[term] << id
                    else
                        byTerm[term] = [id]
                    end
                end
            end
            @profilesDict = byTerm
        end
    end


    # Gets profiles dictionary calculated
    # ===== Return
    # profiles dictionary (clone)
    def get_terms_linked_profiles
        return @profilesDict.clone
    end    


    # Get related profiles to a given term
    # ===== Parameters
    # +term+:: to be checked
    # ===== Returns 
    # profiles which contains given term
    def get_term_linked_profiles(term)
        return @profilesDict[term]
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
            expanded_terms << [[t, self.translate_id(t)], self.get_descendants(t, filter_alternatives).map{|child| [child, self.translate_id(child)]}]
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
        if !relations.select{|term, items| !@stanzas[:terms].include?(term)}.empty?
            warn('Some terms specified are not stored into this ontology. These not correct terms will be stored too')
        end
        if !remove_old_relations
            if !relations.select{|term, items| @items.include?(term)}.empty? && !expand
                warn('Some terms given are already stored. Stored version will be replaced')
            end
        end
        if expand
            @items = self.concatItems(@items,relations)
            # relations.each do |k,v| # MUST UPDATE THIS USING A CONCAT SPECIFIC FUNCTION
            #     if @items.keys.include?(k)
            #         if v.kind_of?(Array)
            #             @items[k] = (@items[k] + v).uniq
            #         elsif v.kind_of?(Hash)
            #             @items.merge!(relations) do |k, oldV, newV| 
            #                if oldV.kind_of?(Array)
            #                  return (oldV + newV).uniq
            #                else
            #                  oldV = [oldV,newV]
            #                end  
            #             end
            #         elsif @items[k].kind_of?(Array) # We suppose a single value/object from here
            #             @items[k] = (@items[k] + [v]).uniq
            #         else
            #             @items[k] = [@items[k],v]
            #         end 
            #     else
            #         @items[k] = v
            #     end
            # end
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
    def concatItems(itemA,itemB)
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
            concatenated = (itemA + itemB).uniq
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
    def set_items_from_dict(dictID, remove_old_relations = false)
        @items = {} if remove_old_relations
        if !@dicts[dictID].nil?
            @items.merge(@dicts[dictID][:byTerm])
        else
            warn('Specified ID is not calculated. Dict will not be added as a items set')
        end
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
        # Check item keys
        if @items.empty?
            warn('Items have been not provided yet')
            return nil
        end
        targetKeys = @items.keys.select{|k| self.exists?(k)}
        if targetKeys.length == 0
            warn('Any item key is allowed')
            return nil
        elsif targetKeys.length < @items.keys.length
            warn('Some item keys are not allowed')
        end

        # Expand to parentals
        targetKeys << targetKeys.map{|t| self.get_ancestors(t, true)}
        targetKeys.flatten!
        targetKeys.uniq!

        # Obtain levels (go from leaves to roots)
        levels = targetKeys.map{|term| self.get_term_level(term)}
        levels.compact!
        levels.uniq!
        levels.sort!
        levels.reverse!
        levels.shift # Leaves are not expandable

        # Expand from leaves to roots
        levels.map do |lvl|
            curr_keys = targetKeys.select{|k| self.get_term_level(k) == lvl}
            curr_keys.map do |term_expand|
                to_infer = []
                # Obtain childs
                childs = self.get_descendants(term_expand,true).select{|t| !@items[t].nil?}
                # Expand
                if childs.length > 0 && minimum_childs == 1 # Special case
                    to_infer = childs.map{|c| @items[c]}.flatten.compact.uniq
                elsif childs.length >= minimum_childs
                    to_infer = Hash.new(0)
                    # Compare
                    while childs.length > 1
                        curr_term = childs.shift
                        childs.each do |compare_term|
                            pivot_items = @items[curr_term]
                            compare_items = @items[compare_term]
                            if ontology.nil? # Exact match
                                pivot_items.map do |pitem|
                                    if compare_items.include?(pitem)
                                        to_infer[pitem] += 2
                                    end
                                end
                            else # Find MICAs
                                local_infer = Hash.new(0)
                                pivot_items.map do |pitem|
                                    micas = compare_items.map{|citem| ontology.get_MICA(pitem, citem)}
                                    maxmica = micas[0]
                                    micas.each{|mica| maxmica = mica if mica.last > maxmica.last}
                                    local_infer[maxmica.first] += 1
                                end
                                compare_items.map do |citem|
                                    micas = pivot_items.map{|pitem| ontology.get_MICA(pitem, citem)}
                                    maxmica = micas[0]
                                    micas.each{|mica| maxmica = mica if mica.last > maxmica.last}
                                    local_infer[maxmica.first] += 1
                                end
                                local_infer.each{|t,freq| to_infer[t] += freq if freq >= 2}
                            end
                        end
                    end
                    # Filter infer
                    to_infer = to_infer.select{|k,v| v >= minimum_childs}
                end
                # Infer
                if to_infer.length > 0
                    @items[term_expand] = [] if @items[term_expand].nil?
                    if to_infer.kind_of?(Array)
                        @items[term_expand] = (@items[term_expand] + to_infer).uniq
                    else
                        @items[term_expand] = (@items[term_expand] + to_infer.keys).uniq
                    end
                    @items[term_expand] = ontology.clean_profile(@items[term_expand]) if clean_profiles && !ontology.nil?
                elsif !@items.include?(term_expand)
                    targetKeys.delete(term_expand)
                end
            end
        end
    end


    # Return direct ancestors/descendants of a given term
    # ===== Parameters
    # +term+:: which are requested
    # +relation+:: can be :ancestor or :descendant 
    # +remove_alternatives+:: if true, alternatives will be removed
    # ===== Returns
    # Direct ancestors/descendants of given term or nil if any error occurs
    def get_direct_related(term, relation, remove_alternatives: false)
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
        return query if query.nil?
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



#============================================================================
#============================================================================

    # NO IDEA WHAT THIS DOES. DON'T USE THIS METHODS IS NOT CHECKED
    # ===== Parameters
    # ++::
    # ===== Returns
    # ...
     def compute_relations_to_items(external_item_list, total_items, mode, thresold)
        terms_levels = list_terms_per_level_from_items 
        #puts terms_levels.inspect.yellow
        connect_familiars!(terms_levels)
        #puts terms_levels.inspect.blue
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
        return groups.compact.inject([]){|it, a| it | a}
    end

    def list_terms_per_level_from_items
        terms_levels = {}
        @items.each do |term, items| 
          level = self.get_term_level(term)
          query = terms_levels[level]
          if query.nil?
            terms_levels[level] = [term]
          else
            query << term
          end
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
#============================================================================

    # Check if a given ID is a removable (blacklist) term.
    # +DEPRECATED+ use is_removable? instead
    # ===== Parameters
    # +id+:: to be checked
    # ===== Returns 
    # true if given term is a removable (blacklist) term or false in other cases
    def is_removable(id)
        warn "[DEPRECATION] `is_removable` is deprecated.  Please use `is_removable?` instead."
        return @removable_terms.include?(id.to_sym)
    end

    # Check if a given ID is a removable (blacklist) term
    # ===== Parameters
    # +id+:: to be checked
    # ===== Returns 
    # true if given term is a removable (blacklist) term or false in other cases
    def is_removable? id
        return @removable_terms.include?(id.to_sym)
    end

    ############################################
    # SPECIAL METHODS
    #############################################
    def ==(other)
        self.header == other.header &&
        self.stanzas == other.stanzas &&
        self.ancestors_index == other.ancestors_index &&
        self.alternatives_index == other.alternatives_index &&
        self.obsoletes_index == other.obsoletes_index &&
        self.structureType == other.structureType &&
        self.ics == other.ics &&
        self.meta == other.meta &&
        self.dicts == other.dicts &&
        self.profiles == other.profiles &&
        self.profilesDict == other.profilesDict &&
        (self.items.keys - other.items.keys).empty? &&
        self.removable_terms == other.removable_terms &&
        self.special_tags == other.special_tags &&
        self.items == other.items &&
        self.term_paths == other.term_paths &&
        self.max_freqs == other.max_freqs
    end


    def clone
        copy = Ontology.new
        copy.header = self.header.clone
        copy.stanzas[:terms] = self.stanzas[:terms].clone
        copy.stanzas[:typedefs] = self.stanzas[:typedefs].clone
        copy.stanzas[:instances] = self.stanzas[:instances].clone
        copy.ancestors_index = self.ancestors_index.clone
        copy.descendants_index = self.descendants_index.clone
        copy.alternatives_index = self.alternatives_index.clone
        copy.obsoletes_index = self.obsoletes_index.clone
        copy.structureType = self.structureType.clone
        copy.ics = self.ics.clone
        copy.meta = self.meta.clone
        copy.dicts = self.dicts.clone
        copy.profiles = self.profiles.clone
        copy.profilesDict = self.profilesDict.clone
        copy.items = self.items.clone
        copy.removable_terms = self.removable_terms.clone
        copy.term_paths = self.term_paths.clone
        copy.max_freqs = self.max_freqs.clone
        return copy
    end

    
    #############################################
    # ACCESS CONTROL
    #############################################

    attr_reader :file, :header, :stanzas, :ancestors_index, :descendants_index, :special_tags, :alternatives_index, :obsoletes_index, :structureType, :ics, :max_freqs, :meta, :dicts, :profiles, :profilesDict, :items, :removable_terms, :term_paths
    attr_writer :file, :header, :stanzas, :ancestors_index, :descendants_index, :special_tags, :alternatives_index, :obsoletes_index, :structureType, :ics, :max_freqs, :meta, :dicts, :profiles, :profilesDict, :items, :removable_terms, :term_paths
end
