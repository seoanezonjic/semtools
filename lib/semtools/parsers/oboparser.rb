class OboParser < FileParser

    #############################################
    # FIELDS
    #############################################
    # => @header :: file header (if is available)
    # => @stanzas :: OBO stanzas {:terms,:typedefs,:instances}
    # => @ancestors_index :: hash of ancestors per each term handled with any structure relationships
    # => @descendants_index :: hash of descendants per each term handled with any structure relationships
    # => @alternatives_index :: has of alternative IDs (include alt_id and obsoletes)
    # => @special_tags :: set of special tags to be expanded (:is_a, :obsolete, :alt_id)
    # => @structureType :: type of ontology structure depending on ancestors relationship. Allowed: {atomic, sparse, circular, hierarchical}
    # => @dicts :: bidirectional dictionaries with three levels <key|value>: 1º) <tag|hash2>; 2º) <(:byTerm/:byValue)|hash3>; 3º) dictionary <k|v>
    # => @removable_terms :: array of terms to not be considered

    @@header = nil
    @@stanzas = {terms: {}, typedefs: {}, instances: {}}
    @@removable_terms = []
    @@alternatives_index = {}
    @@obsoletes = {}
    @@structureType = nil
    @@ancestors_index = {}
    @@descendants_index = {}
    @@reroot = false
    @@dicts = {}

    def self.reset
        @@header = nil
        @@stanzas = {terms: {}, typedefs: {}, instances: {}}
        @@removable_terms = []
        @@alternatives_index = {}
        @@obsoletes = {}
        @@structureType = nil
        @@ancestors_index = {}
        @@descendants_index = {}
        @@reroot = false
        @@dicts = {}
    end

    def self.each(att = false, only_main = true)
        warn('stanzas terms empty') if @@stanzas[:terms].empty?
        @@stanzas[:terms].each do |id, tags|            
            next if only_main && (@@alternatives_index.include?(id) || @@obsoletes.include?(id))
            if att
               yield(id, tags)
            else
               yield(id)
            end
        end
    end

	def self.load(ontology, file, build: true, black_list: [], extra_dicts: [])
        reset # Clean class variables to avoid the mix of several obo loads
        @@removable_terms = black_list
		_, header, stanzas = self.load_obo(file)
        @@header = header
        @@stanzas = stanzas
        self.remove_black_list_terms() if !@@removable_terms.empty?
        self.build_index(ontology, extra_dicts: extra_dicts) if build
	end

	# Class method to load an OBO format file (based on OBO 1.4 format). Specially focused on load
    # the Header, the Terms, the Typedefs and the Instances.
    # ===== Parameters
    # +file+:: OBO file to be loaded
    # ===== Returns 
    # Hash with FILE, HEADER and STANZAS info
    def self.load_obo(file) 
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
            value.gsub!(/{[\\\":A-Za-z0-9\/\.\-, =?&_]+} /, '') if tag == 'is_a' # To delete extra attributes (source, xref) in is_a tag of MONDO ontology
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

    def self.remove_black_list_terms()
        @@removable_terms.each{|removableID| @@stanzas[:terms].delete(removableID)}
    end

    # Executes basic expansions of tags (alternatives, obsoletes and parentals) with default values
    # ===== Returns 
    # true if eprocess ends without errors and false in other cases
    def self.build_index(ontology, extra_dicts: [])
        self.get_index_obsoletes
        self.get_index_alternatives
        self.remove_obsoletes_in_terms
        self.get_index_child_parent_relations
        @@alternatives_index.transform_values!{|v| self.extract_id(v)}
        @@alternatives_index.compact!
        @@ancestors_index.each{|k,v| @@ancestors_index[k] = v.map{|t| self.extract_id(t)}.compact}
        @@descendants_index.each{|k,v| @@descendants_index[k] = v.map{|t| self.extract_id(t)}.compact}
        self.calc_dictionary(:name)
        self.calc_dictionary(:synonym, select_regex: /\"(.*)\"/)
        self.calc_ancestors_dictionary
        extra_dicts.each do |dict_tag, extra_parameters|
            self.calc_dictionary(dict_tag, **extra_parameters) # https://www.justinweiss.com/articles/fun-with-keyword-arguments/
        end
        ontology.terms = @@stanzas[:terms]
        ontology.alternatives_index = @@alternatives_index
        ontology.obsoletes = @@obsoletes
        ontology.ancestors_index = @@ancestors_index
        ontology.descendants_index = @@descendants_index
        ontology.reroot = @@reroot
        ontology.structureType = @@structureType
        ontology.dicts = @@dicts

    end

    def self.remove_obsoletes_in_terms() # once alternative and obsolete indexes are loaded, use this to keep only working terms
        terms = @@stanzas[:terms]
        @@obsoletes.each do |term, val|
            terms.delete(term)
        end
    end


    # Expand obsoletes set and link info to their alternative IDs
    # ===== Parameters
    # +obs_tags+:: tags to be used to find obsoletes
    # +alt_tags+:: tags to find alternative IDs (if are available)
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def self.get_index_obsoletes(obs_tag: @@basic_tags[:obsolete], alt_tags: @@basic_tags[:alternative])
        each(att = true) do |id, term_tags|
            obs_value = term_tags[obs_tag]
            if obs_value == 'true' # Obsolete tag presence, must be checked as string
                alt_ids = alt_tags.map{|alt| term_tags[alt]}.compact # Check if alternative value is available
                if !alt_ids.empty?
                    alt_id = alt_ids.first.first #FIRST tag, FIRST id 
                    @@alternatives_index[id] = alt_id
                end
                @@obsoletes[id] = true
            end
        end
    end

    # Expand alternative IDs arround all already stored terms
    # ===== Parameters
    # +alt_tag+:: tag used to expand alternative IDs
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def self.get_index_alternatives(alt_tag: @@basic_tags[:alternative].last)
        each(att = true) do |id, tags|
            alt_ids = tags[alt_tag]
            if !alt_ids.nil?
                alt_ids = alt_ids - @@removable_terms - [id]
                alt_ids.each do |alt_term|
                    @@alternatives_index[alt_term] = id
                end
            end
        end
    end

    # Expand parentals set. Also launch frequencies process
    # ===== Parameters
    # +tag+:: tag used to expand parentals
    # ===== Returns 
    # true if process ends without errors and false in other cases
    def self.get_index_child_parent_relations(tag: @@basic_tags[:ancestors][0])
        structType, parentals = self.get_related_ids_by_tag(terms: @@stanzas[:terms],
                                                        target_tag: tag,
                                                        reroot: @@reroot)    
        if structType.nil? || parentals.nil?
            raise('Error expanding parentals')
        elsif ![:atomic,:sparse].include?(structType) # Check structure
            structType = structType == :circular ? :circular : :hierarchical
        end
        @@structureType = structType 

        parentals.each do |id, parents|
            parents = parents - @@removable_terms
            @@ancestors_index[id] = parents
            parents.each{|anc_id| self.add2hash(@@descendants_index, anc_id, id)}
        end
    end


    # Expand terms using a specific tag and return all extended terms into an array and
    # the relationship structuture observed (hierarchical or circular). If circular structure is
    # foumd, extended array will be an unique vector without starting term (no loops) 
    # ===== Parameters
    # +terms+:: set to be used to expand
    # +target_tag+:: tag used to expand
    # ===== Returns 
    # A vector with the observed structure (string) and the hash with extended terms
    def self.get_related_ids_by_tag(terms:, target_tag:, reroot: false)
        structType = :hierarchical
        related_ids = {}
        terms.each do |id, tags|
            if !tags[target_tag].nil?
                set_structure, _ = self.get_related_ids(id, terms, target_tag, related_ids)                        
                structType = :circular if set_structure == :circular # Check structure
            end
        end

        # Check special case
        structType = :atomic if related_ids.length <= 0
        structType = :sparse if reroot || (related_ids.length > 0 && ((terms.length - related_ids.length ) >= 2) )
        return structType, related_ids
    end

    # Expand a (starting) term using a specific tag and return all extended terms into an array and
    # the relationship structuture observed (hierarchical or circular). If circular structure is
    # foumd, extended array will be an unique vector without starting term (no loops).
    # +Note+: we extremly recomend use get_related_ids_by_tag function instead of it (directly)
    # ===== Parameters
    # +start+:: term where start to expand
    # +terms+:: set to be used to expand
    # +target_tag+:: tag used to expand
    # +eexpansion+:: already expanded info
    # ===== Returns 
    # A vector with the observed structure (string) and the array with extended terms.
    def self.get_related_ids(start_id, terms, target_tag, related_ids = {})
        # Take start_id term available info and already accumulated info
        current_associations = related_ids[start_id]
        current_associations = [] if current_associations.nil? 
        return [:no_term,[]] if terms[start_id].nil?
        id_relations = terms[start_id][target_tag]
        return [:source,[]] if id_relations.nil?

        struct = :hierarchical

        # Study direct extensions
        id_relations.each do |id|        
            # Handle
            if current_associations.include?(id) # Check if already have been included into this expansion
                struct = :circular
            else
                current_associations << id 
                if related_ids.include?(id) # Check if current already has been expanded
                    current_associations = current_associations | related_ids[id]
                    if current_associations.include?(start_id) # Check circular case
                        struct = :circular
                        current_associations = current_associations - [id, start_id]
                    end    
                else # Expand
                    related_ids[start_id] = current_associations
                    structExp, current_related_ids = self.get_related_ids(id, terms, target_tag, related_ids) # Expand current
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

    # Calculates :is_a dictionary 
    def self.calc_ancestors_dictionary
        self.calc_dictionary(:is_a, self_type_references: true, multiterm: true)
    end

    # Generate a bidirectinal dictionary set using a specific tag and terms stanzas set
    # This functions stores calculated dictionary into @dicts field.
    # This functions stores first value for multivalue tags
    # This function does not handle synonyms for byValue dictionaries
    # ===== Parameters
    # +tag+:: to be used to calculate dictionary
    # +select_regex+:: gives a regfex that can be used to modify value to be stored
    # +store_tag+:: flag used to store dictionary. If nil, mandatory tag given will be used
    # +multiterm+:: if true, byValue will allows multi-term linkage (array)
    # +self_type_references+:: if true, program assumes that refrences will be between Ontology terms, and it term IDs will be checked
    # ===== Return
    # hash with dict data. And stores calcualted bidirectional dictonary into dictionaries main container
    def self.calc_dictionary(tag, select_regex: nil, store_tag: nil, multiterm: false, self_type_references: false)
        tag = tag.to_sym
        store_tag = tag if store_tag.nil?

        byTerm = {}
        byValue = {}
        # Calc per term
        each(att = true, only_main = false) do |term, tags|
            referenceTerm = term
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
                referenceValue = @@stanzas[:terms][term][tag]
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
        dict = {byTerm: byTerm, byValue: byValue}
        @@dicts[store_tag] = dict
        return dict
    end

    # Check if a given ID is stored as term into this object
    # ===== Parameters
    # +id+:: to be checked 
    # ===== Return
    # True if term is allowed or false in other cases
    def self.exists? id
        return @@stanzas[:terms].include?(id)
    end

    # Check if a term given is marked as obsolete
    def self.is_obsolete? term
        return @@obsoletes.include?(term)
    end

    # Check if a term given is marked as alternative
    def self.is_alternative? term
        return @@alternatives_index.include?(term)
    end

    # This method assumes that a text given contains an allowed ID. And will try to obtain it splitting it
    # ===== Parameters
    # +text+:: to be checked 
    # ===== Return
    # The correct ID if it can be found or nil in other cases
    def self.extract_id(text, splitBy: ' ')
        if self.exists?(text)
            return text
        else
            splittedText = text.to_s.split(splitBy).first.to_sym
            return self.exists?(splittedText) ? splittedText : nil
        end
    end


    private

    def self.add2hash(hash, key, val)
        query = hash[key]
        if query.nil?
            hash[key] = [val]
        else
            query << val
        end
    end    

end
