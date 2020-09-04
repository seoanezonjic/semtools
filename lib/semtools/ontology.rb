require 'json'

#########################################################
# AUTHOR NOTES
#########################################################

# 1 - Store @profiles as @stanzas[:instances]
# 2 - Items values (not keys) are imported as strings, not as symbols (maybe add a flag which indicates if values are, or not, symbols?) 

class Ontology
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
	# => @alternatives_index :: has of alternative IDs (includee alt_id and obsoletes)
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

	@@basic_tags = {ancestors: [:is_a], obsolete: :is_obsolete, alternative: [:alt_id,:replaced_by,:consider]}
	@@allowed_calcs = {ics: [:resnick, :resnick_observed, :seco, :zhou, :sanchez], sims: [:resnick, :lin, :jiang_conrath]}
	@@symbolizable_ids = [:id, :alt_id, :replaced_by, :consider]
	@@tags_with_trailing_modifiers = [:is_a, :union_of, :disjoint_from, :relationship, :subsetdef, :synonymtypedef, :property_value]
	@@multivalue_tags = [:alt_id, :is_a, :subset, :synonym, :xref, :intersection_of, :union_of, :disjoint_from, :relationship, :replaced_by, :consider, :subsetdef, :synonymtypedef, :property_value]
	@@symbolizable_ids.concat(@@tags_with_trailing_modifiers)
	
	#############################################
	# CONSTRUCTOR
	#############################################
	
	# Instantiate a OBO_Handler object
	# Params:
	# +file+:: with info to be loaded (.obo ; .json)
	# +load:p+:: activate load process automatically (only for .obo)
	def initialize(file: nil, load_file: false, removable_terms: [])
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
		# Load if proceeds
		add_removable_terms(removable_terms) if !removable_terms.empty?
		load(file) if load_file
	end


	#############################################
	# CLASS METHODS
	#############################################

	# Expand a (starting) term using a specific tag and return all extended terms into an array and
	# the relationship structuture observed (hierarchical or circular). If circular structure is
	# foumd, extended array will be an unique vector without starting term (no loops) 
	# Param:
	# +start+:: term where start to expand
	# +terms+:: set to be used to expand
	# +target_tag+:: tag used to expand
	# +eexpansion+:: already expanded info
	# +split_info_char+:: special regex used to split info (if it is necessary)
	# +split_info_indx+:: special index to take splitted info (if it is necessary)
	# +alt_ids+:: set of alternative IDs
	# Returns a vector with the observed structure (string) and the array with extended terms
	# Note: we extremly recomend use get_related_ids_by_tag function instead of it (directly)
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
	# Param:
	# +terms+:: set to be used to expand
	# +target_tag+:: tag used to expand
	# +split_info_char+:: special regex used to split info (if it is necessary)
	# +split_info_indx+:: special index to take splitted info (if it is necessary)
	# +alt_ids+:: set of alternative IDs
	# +obsoletes+:: integer with the number of obsolete IDs. used to calculate structure type.
	# Returns a vector with the observed structure (string) and the hash with extended terms
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
	# Param:
	# +attributes+:: array tuples with info to be transformed into hash format
	# Return attributes stored into hash structure
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
					query << value	# Add new value to tag
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
	# Param:
	# +file+:: OBO file to be loaded
	# Returns hash with FILE, HEADER and STANZAS info
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
	# Params:
	# +header+:: container
	# +infoType+:: current ontology item type detected
	# +stanzas+:: container
	# +currInfo+:: info to be stored
	# Returns :: header newly/already stored
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
	# Params:
	# +item_hash+:: hash to be checked
	# Return :: void
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






	#############################################
	# GENERAL METHODS
	#############################################

	# Include removable terms to current removable terms list
	# Params:
	# +terms+:: terms array to be concatenated
	# Return :: void 
	def add_removable_terms(terms)
		terms = terms.map{|term| term.to_sym}
		@removable_terms.concat(terms)
	end


	# Include removable terms to current removable terms list loading new
	# terms from a one column plain text file
	# Params:
	# +file+:: to be loaded 
	# Return :: void
	def add_removable_terms_from_file(file)
		File.open(excluded_codes_file).each do |line|
			line.chomp!
			@removable_terms << line.to_sym
		end
	end

	
	# Increase observed frequency for a specific term
	# Params:
	# +term+:: term which frequency is going to be increased
	# +increas+:: frequency rate to be increased. Default = 1
	# Return :: true if process ends without errors, false in other cases
	def add_observed_term(term:,increase: 1.0)
		# Check
		raise ArgumentError, "Term given is NIL" if term.nil?
		return false unless @stanzas[:terms].include?(term)
		return false if @removable_terms.include?(term)
		if @alternatives_index.include?(term)
			alt_id = @alternatives_index[term]
			@meta[alt_id] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:observed_freq => -1.0} if @meta[alt_id].nil?
			@meta[term] = @meta[alt_id] 			
		end
		# Check if exists
		@meta[term] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:observed_freq => -1.0} if @meta[term].nil?
		# Add frequency
		@meta[term][:observed_freq] = 0 if @meta[term][:observed_freq] == -1
		@meta[term][:observed_freq] += increase
		# Check maximum frequency
		@max_freqs[:observed_freq] = @meta[term][:observed_freq] if @max_freqs[:observed_freq] < @meta[term][:observed_freq]  
		return true
	end


	# Increase the arbitrary frequency of a given term set 
	# Params:
	# +terms+:: set of terms to be updated
	# +increase+:: amount to be increased
	# +transform_to_sym+:: if true, transform observed terms to symbols. Default: false
	# Return :: true if process ends without errors and false in other cases
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
	# Params
	# +termsA+:: set to be compared
	# +termsB+:: set to be compared
	# +sim_type+:: similitude method to be used. Default: resnick
	# +ic_type+:: ic type to be used. Default: resnick
	# +bidirectional+:: calculate bidirectional similitude. Default: false
	# Return :: similitude calculated
	def compare(termsA:, termsB:, sim_type: :resnick, ic_type: :resnick, bidirectional: false)
		# Check
		raise ArgumentError, "Terms sets given are NIL" if termsA.nil? | termsB.nil?
		micasA = []
		# Compare A -> B
		termsA.each do |tA|
			micas = termsB.map{|tB| self.get_similarity(termA: tA,termB: tB, type: sim_type, ic_type: ic_type)}
			# Remove special cases
			[false,nil].each do |err_value| micas.delete(err_value) end
			# Obtain maximum value
			micasA << micas.max if micas.length > 0
			micasA << 0 if micas.length <= 0
		end
		means_sim = [micasA.inject{ |sum, el| sum + el }.to_f / micasA.size]
		# Compare B -> A
		means_sim << self.compare(termsA: termsB, termsB: termsA, sim_type: sim_type, ic_type: ic_type) if bidirectional
		# Return
		return means_sim.inject{ |sum, el| sum + el }.to_f / means_sim.size
	end


	# Expand alternative IDs arround all already stored terms
	# Params:
	# +alt_tag+:: tag used to expand alternative IDs
	# Returns true if process ends without errors and false in other cases
	def get_index_alternatives(alt_tag: @@basic_tags[:alternative][0])
		# Check input
		raise('stanzas terms empty')  if @stanzas[:terms].empty?
		# Take all alternative IDs
		alt_ids2add = {}
		@stanzas[:terms].each do |id, tags|
			alt_ids = tags[alt_tag]
			if !alt_ids.nil?
				alt_ids = alt_ids - @removable_terms
				# Update info
				alt_ids.each do |alt_term|
					@alternatives_index[alt_term] = id
					alt_ids2add[alt_term] = @stanzas[:terms][id] if !@stanzas[:terms].include?(alt_term)
					@ancestors_index[alt_term] = @ancestors_index[id] if !@ancestors_index[id].nil?
				end
			end
		end
		@stanzas[:terms].merge!(alt_ids2add)
	end


	# Executes basic expansions of tags (alternatives, obsoletes and parentals) with default values
	# Returns :: true if eprocess ends without errors and false in other cases
	def build_index()
		self.get_index_alternatives
		self.get_index_obsoletes
		self.get_index_child_parent_relations
		self.get_index_frequencies
		self.calc_dictionary(:name)
		self.calc_dictionary(:synonym, select_regex: /\"(.*)\"/)
		self.calc_term_levels
	end


	# Calculates regular frequencies based on ontology structure (using parentals)
	# Returns :: true if everything end without errors and false in other cases
	def get_index_frequencies()
		# Check
		if @ancestors_index.empty?
			warn('ancestors_index object is empty') 
		else
			# Prepare useful variables
			alternative_terms = @alternatives_index.keys
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
					query[:ancestors] = @ancestors_index.include?(id) ? @ancestors_index[id].count{|anc| !alternative_terms.include?(anc)}.to_f : 0.0
					query[:descendants] = @descendants_index.include?(id) ? @descendants_index[id].count{|desc| !alternative_terms.include?(desc)}.to_f : 0.0
					query[:struct_freq] = query[:descendants] + 1.0
					# Update maximums
					@max_freqs[:struct_freq] = query[:struct_freq] if @max_freqs[:struct_freq] < query[:struct_freq]  
					@max_freqs[:max_depth] = query[:descendants] if @max_freqs[:max_depth] < query[:descendants]  
				end
			end
		end
	end


	# Expand obsoletes set and link info to their alternative IDs
	# Params:
	# +obs_tags+:: tags to be used to find obsoletes
	# +alt_tags+:: tags to find alternative IDs (if are available)
	# +reset_obsoletes+:: flag to indicate if obsoletes set must be reset. Default: true
	# Returns true if process ends without errors and false in other cases
	def get_index_obsoletes(obs_tag: @@basic_tags[:obsolete], alt_tags: @@basic_tags[:alternative])
		if @stanzas[:terms].empty?
			warn('stanzas terms empty')
		else
			# Check obsoletes
			@stanzas[:terms].each do |id, term_tags|
				next if term_tags.nil?
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
	# Params:
	# +tag+:: tag used to expand parentals
	# +split_info_char+:: special regex used to split info (if it is necessary)
	# +split_info_indx+:: special index to take splitted info (if it is necessary)
	# Returns true if process ends without errors and false in other cases
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
	# Params:
	# +term+:: to be checked
	# +filter_alternatives+:: if true, remove alternatives from final results
	# Returns an array with all ancestors of given term or false if parents are not available yet
	def get_ancestors(term, filter_alternatives = false)
		return self.get_familiar(term, true, filter_alternatives)		
	end


	# Find descendants of a given term
	# Params:
	# +term+:: to be checked
	# +filter_alternatives+:: if true, remove alternatives from final results
	# Returns an array with all descendants of given term or false if parents are not available yet
	def get_descendants(term, filter_alternatives = false)
		return self.get_familiar(term, false, filter_alternatives)		
	end


	# Find ancestors/descendants of a given term
	# Params:
	# +term+:: to be checked
	# +return_ancestors+:: return ancestors if true or descendants if false
	# +filter_alternatives+:: if true, remove alternatives from final results
	# Returns an array with all ancestors/descendants of given term or nil if parents are not available yet
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
	# Params:
	# +term+:: which IC will be calculated
	# +type+:: of IC to be calculated. Default: resnick
	# +force+:: force re-calculate the IC. Do not check if it is already calculated
	# +zhou_k+:: special coeficient for Zhou IC method
	# Returns the IC calculated
	def get_IC(termRaw, type: :resnick, force: false, zhou_k: 0.5)
		term = termRaw.to_sym
		# Check 
		raise ArgumentError, "IC type specified (#{type}) is not allowed" if !@@allowed_calcs[:ics].include?(type)
		# Check if it's already calculated
		return @ics[type][term] if (@ics[type].include? term) && !force
		# Calculate
		ic = - 1
		case type
			when :resnick
				# -log(Freq(x) / Max_Freq)
				ic = -Math.log10(@meta[term][:struct_freq].fdiv(@max_freqs[:struct_freq]))
			when :resnick_observed
				# -log(Freq(x) / Max_Freq)
				ic = -Math.log10(@meta[term][:observed_freq].fdiv(@max_freqs[:observed_freq]))
			when :seco, :zhou
				#  1 - ( log(hypo(x) + 1) / log(max_nodes) )
				ic = 1 - Math.log10(@meta[term][:struct_freq]).fdiv(Math.log10(@stanzas[:terms].length - @alternatives.length))
				if :zhou				
					# k*(IC_Seco(x)) + (1-k)*(log(depth(x))/log(max_depth))
					@ics[:seco][term] = ic # Special store
					ic = zhou_k * ic + (1.0 - zhou_k) * (Math.log10(@meta[term][:descendants]).fdiv(Math.log10(@max_freqs[:max_depth])))
				end
			when :sanchez
				ic = -Math.log10((@meta[term][:descendants].fdiv(@meta[term][:ancestors]) + 1.0).fdiv(@max_freqs[:max_depth] + 1.0))
		end			
		@ics[type][term] = ic
		return ic
	end


	# Calculates and return resnick ICs (by ontology and observed frequency) for observed terms
	# Returns two hashes with resnick and resnick_observed ICs for observed terms
	def get_observed_ics_by_onto_and_freq
		# Chech there are observed terms
		if @profiles.empty?
			resnick = {}
			resnick_observed = {}
		else
			# Calc ICs for all terms
			observed_terms = @profiles.values.flatten.uniq
			observed_terms.each{ |term| get_IC(term)}
			observed_terms.each{ |term| get_IC(term, type: :resnick_observed)}
			resnick = @ics[:resnick].select{|k,v| observed_terms.include?(k)}
			resnick_observed = @ics[:resnick_observed].select{|k,v| observed_terms.include?(k)}
		end
		return resnick.clone, resnick_observed.clone
	end


	# Find the IC of the Most Index Content shared Ancestor (MICA) of two given terms
	# Params:
	# +termA+:: term to be cheked
	# +termB+:: term to be checked
	# +ic_type+:: IC formula to be used
	# Returns the IC of the MICA(termA,termB)
	def get_ICMICA(termA, termB, ic_type = :resnick)
		mica = self.get_MICA(termA, termB, ic_type)
		return mica.first.nil? ? nil : mica.last
	end


	# Find the Most Index Content shared Ancestor (MICA) of two given terms
	# Params:
	# +termA+:: term to be cheked
	# +termB+:: term to be checked
	# +ic_type+:: IC formula to be used
	# Returns the MICA(termA,termB) and it's IC
	def get_MICA(termA, termB, ic_type = :resnick)
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
	# Params:
	# +termsA+:: to be compared
	# +termsB+:: to be compared
	# +type+:: similitude formula to be used
	# +ic_type+:: IC formula to be used
	# Returns the similarity between both sets or false if frequencies are not available yet
	def get_similarity(termA, termB, type: :resnick, ic_type: :resnick)
		# Check
		raise ArgumentError, "SIM type specified (#{type}) is not allowed" if !@@allowed_calcs[:sims].include?(type)
		sim = nil
		# Launch comparissons
		sim_res = get_ICMICA(termA, termB, ic_type)
		if !sim_res.nil?
			case type
				when :resnick
					sim = sim_res
				when :lin
					sim = (2.0 * sim_res).fdiv(self.get_IC(termA,type: ic_type) + self.get_IC(termB,type: ic_type))
				when :jiang_conrath
					sim = (self.get_IC(termA, type: ic_type) + self.get_IC(termB, type: ic_type)) - (2.0 * sim_res)
			end
		end
		return sim
	end


	# Method used to load information stored into an OBO file and store it into this object.
	# If a file is specified by input parameter, current @file value is updated
	# Param
	# +file+:: optional file to update object stored file
	# Return :: void
	def load(file)
		_, header, stanzas = self.class.load_obo(file)
		@header = header
		@stanzas = stanzas
		@removable_terms.each{|removableID| @stanzas[:terms].delete(removableID)} if !@removable_terms.empty? # Remove if proceed
		self.build_index() 
	end


	# Exports an OBO_Handler object in json format
	# Params:
	# +file+:: where info will be stored
	# Return :: void
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
					removable_terms: @removable_terms}
		# Convert to JSON format & write
		File.open(file, "w") { |f| f.write obj_info.to_json }
	end


	# Read a JSON file with an OBO_Handler object stored
	# Params:
	# +file+:: with object info
	# Return :: OBO_Handler internal fields 
	def read(file)
		# Read file
		jsonFile = File.open(file)
		jsonInfo = JSON.parse(jsonFile.read, :symbolize_names => true)
		# Pre-process (Symbolize some hashs values)
		jsonInfo[:stanzas][:terms].map{|id,info| self.class.symbolize_ids(info)} # STANZAS
		jsonInfo[:stanzas][:typedefs].map{|id,info| self.class.symbolize_ids(info)}
		jsonInfo[:stanzas][:instances].map{|id,info| self.class.symbolize_ids(info)}
		jsonInfo[:alternatives_index] = jsonInfo[:alternatives_index].map{|id,value| [id, value.to_sym]}.to_h 
		jsonInfo[:ancestors_index].map {|id,family_arr| family_arr.map!{|item| item.to_sym}}
		jsonInfo[:descendants_index].map {|id,family_arr| family_arr.map!{|item| item.to_sym}}
		jsonInfo[:obsoletes_index] = jsonInfo[:obsoletes_index].map{|id,value| [id, value.to_sym]}.to_h
		jsonInfo[:dicts] = jsonInfo[:dicts].each do |flag, dictionaries|
			# Special case: byTerm
			dictionaries[:byTerm] = dictionaries[:byTerm].map do |term, value| 
				if !term.to_s.scan(/\A[-+]?[0-9]*\.?[0-9]+\Z/).empty?  # Numeric dictionary
					[term.to_s.to_i, value.map{|term| term.to_sym}]
				elsif value.is_a? Numeric # Numeric dictionary
					[term.to_sym, value]
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
				else
					[value.to_s, term.to_sym]
				end
			end
			dictionaries[:byValue] = dictionaries[:byValue].to_h
		end 
		jsonInfo[:profiles].map{|id,terms| terms.map!{|term| term.to_sym}}
		jsonInfo[:profilesDict].map{|term,ids| ids.map!{|id| id.to_sym}}
		jsonInfo[:removable_terms] = jsonInfo[:removable_terms].map{|term| term.to_sym}
		# Store info
		@header = jsonInfo[:header]
		@stanzas = jsonInfo[:stanzas]
		@ancestors_index = jsonInfo[:ancestors_index]
		@descendants_index = jsonInfo[:descendants_index]
		@alternatives_index = jsonInfo[:alternatives_index]
		@obsoletes_index = jsonInfo[:obsoletes_index]
		@structureType = jsonInfo[:structureType].to_sym
		@ics = jsonInfo[:ics]
		@meta = jsonInfo[:meta]
		@special_tags = jsonInfo[:special_tags]
		@max_freqs = jsonInfo[:max_freqs]
		@dicts = jsonInfo[:dicts]
		@profiles = jsonInfo[:profiles]
		@profilesDict = jsonInfo[:profilesDict]
		@items = jsonInfo[:items]
		@removable_terms = jsonInfo[:removable_terms]
	end

	# Generate a bidirectinal dictionary set using a specific tag and terms stanzas set
	# This functions stores calculated dictionary into @dicts field.
	# This functions stores first value for multivalue tags
	# This function does not handle synonyms for byValue dictionaries
	# Params:
	# +tag+:: to be used to calculate dictionary
	# +select_regex+:: gives a regfex that can be used to modify value to be stored
	# Return :: void. And stores calcualted bidirectional dictonary into dictionaries main container
	def calc_dictionary(tag, select_regex: nil)
		if @stanzas[:terms].empty?
			warn('Terms are not already loaded. Aborting dictionary calc') 
		else
			byTerm = {}
			byValue = {}
			# Calc per term
			@stanzas[:terms].each do |term, tags|
				referenceTerm = term
				if !@alternatives_index[term].nil? # Special case
					referenceTerm = @alternatives_index[term]
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
					end
					if queryTag.kind_of?(Array) # Store
						byTerm[referenceTerm] = queryTag
						queryTag.each{|value| byValue[value] = referenceTerm}
					else
						byTerm[referenceTerm] = [queryTag]
						byValue[queryTag] = referenceTerm
					end
				end
			end
			@dicts[tag] = {byTerm: byTerm, byValue: byValue}
		end
	end


	# Translate a given value using an already calcualted dictionary
	# Params:
	# +toTranslate+:: value to be translated using dictiontionary
	# +tag+:: used to generate the dictionary
	# +byValue+:: boolean flag to indicate if dictionary must be used values as keys or terms as keys. Default: values as keys = true
	# Return :: translation
	def translate(toTranslate, tag, byValue: true)
		dict = byValue ? @dicts[tag][:byValue] : @dicts[tag][:byTerm]	
		toTranslate =  get_main_id(toTranslate) if !byValue
		return dict[toTranslate]
	end


	# Translate a name given
	# Params:
	# +name+:: to be translated
	# Return :: translated name or nil if it's not stored into this ontology
	def translate_name(name)
		term = self.translate(name, :name)
		term = self.translate(name, :synonym) if term.nil?
		return term			
	end


	# Translate several names and return translations and a list of names which couldn't be translated
	# Params:
	# +names+:: array to be translated
	# Return :: two arrays with translations and names which couldn't be translated respectively
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
	# Params:
	# +id+:: to be translated
	# Return :: main name or nil if it's not included into this ontology
	def translate_id(id)
		name = self.translate(id, :name, byValue: false)
		return name.nil? ? nil : name.first
	end


	# Translates several IDs and returns translations and not allowed IDs list
	# Params:
	# +ids+:: to be translated
	# Return :: two arrays with translations and names which couldn't be translated respectively
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


	# Returns the main ID assigned to a given ID. If it's a non alternative/obsolete ID itself will be returned
	# Params:
	# +id+:: to be translated
	# Return :: main ID related to a given ID. Returns nil if given ID is not an allowed ID
	def get_main_id(id)
		return nil if !@stanzas[:terms].include? id
		new_id = id
		mainID = @alternatives_index[id]
		new_id = mainID if !mainID.nil?
		return new_id
	end


	# Check a pull of IDs and return allowed IDs removing which are not official terms on this ontology
	# Params:
	# +ids+:: to be checked
	# Return :: two arrays whit allowed and rejected IDs respectively
	def check_ids(ids)
		checked_codes = []
		rejected_codes = []
		ids.each do |id|
			if @stanzas[:terms].include? id
				checked_codes << id
			else
				rejected_codes << id
			end
		end
		return checked_codes, rejected_codes
	end


	# Stores a given profile with an specific ID. If ID is already assigend to a profile, it will be replaced
	# Params:
	# +id+:: assigned to profile
	# +terms+:: array of terms
	# Return :: void
	def add_profile(id, terms)
		warn("Profile assigned to ID (#{id}) is going to be replaced") if @profiles.include? id
		correct_terms, rejected_terms = self.check_ids(terms)
		if !rejected_terms.empty?
			warn('Given terms contains erroneus IDs. These IDs will be removed')
		end
		@profiles[id.to_sym] = correct_terms  
	end	


	# Returns profiles assigned to a given ID
	# Params:
	# +id+:: profile ID
	# Return :: specific profile or nil if it's not stored
	def get_profile(id)
		return @profiles[id]
	end	


	# Returns an array of sizes for all stored profiles
	# Return :: array of profile sizes
	def get_profiles_sizes()
		return @profiles.map{|id,terms| terms.length}
	end


	# Returns mean size of stored profiles
	# Params:
	# +round_digits+:: number of digits to round result. Default: 4
	# Returns :: mean size of stored profiles
	def get_profiles_mean_size(round_digits: 4)
		sizes = self.get_profiles_sizes
		return sizes.inject(0){|sum, n| sum + n}.fdiv(@profiles.length).round(round_digits)
	end


	# Calculates profiles sizes and returns size assigned to percentile given
	# Params:
	# +perc+:: percentile to be returned
	# +increasing_sort+:: flag to indicate if sizes order must be increasing. Default: false
	# Returns :: values assigned to percentile asked
	def get_profile_length_at_percentile(perc=50, increasing_sort: false)
		prof_lengths = self.get_profiles_sizes.sort
		prof_lengths.reverse! if !increasing_sort
		n_profiles = prof_lengths.length 
		percentile_index = ((perc * (n_profiles - 1)).fdiv(100) - 0.5).round # Take length which not overpass percentile selected
		percentile_index = 0 if percentile_index < 0 # Special case (caused by literal calc)
		return prof_lengths[percentile_index]
	end


	# Translate a given profile to terms names
	# Params:
	# +prof+:: array of terms to be translated
	# Returns :: array of translated terms. Can include nils if some IDs are not allowed
	def profile_names(prof)
		return prof.map{|term| self.translate_id(term)}
	end


	# Trnaslates a bunch of profiles to it sets of term names
	# Params:
	# +profs+:: array of profiles
	# +asArray+:: flag to indicate if results must be returned as: true => an array of tuples [ProfID, ArrayOdNames] or ; false => hashs of translations
	# Returns translated profiles
	def translate_profiles_ids(profs = [], asArray: true)
		profs = @profiles if profs.empty?
		profs = profs.each_with_index.map{|terms, index| [index, terms]}.to_h if profs.kind_of?(Array)
		profs_names = profs.map{|id, terms| [id, self.profile_names(terms)]}.to_h
		return asArray ? profs_names.values : profs_names
	end


	# Includes as "observed_terms" all terms included into stored profiles
	# Params:
	# +reset+:: if true, reset observed freqs alreeady stored befor re-calculate
	# Returns :: void
	def add_observed_terms_from_profiles(reset: false)
		@meta.each{|term, freqs| freqs[:observed_freq] = -1} if reset
		@profiles.each{|id, terms| self.add_observed_terms(terms: terms)}
	end


	# Get a term frequency
	# Params:
	# +term+:: term to be checked
	# +type+:: type of frequency to be returned. Allowed: [:struct_freq, :observed_freq]
	# Returns :: frequency of term given or nil if term is not allowed
	def get_frequency(term, type: :struct_freq)
		queryFreq = @meta[term]
		return queryFreq.nil? ? nil : queryFreq[type]		
	end


	# Returns structural frequency of a term given
	# Params:
	# +term+:: to be checked
	# Returns :: structural frequency of given term or nil if term is not allowed
	def get_structural_frequency(term)
		return self.get_frequency(term, type: :struct_freq)
	end


	# Returns observed frequency of a term given
	# Params:
	# +term+:: to be checked
	# Returns :: observed frequency of given term or nil if term is not allowed
	def get_observed_frequency(term)
		return self.get_frequency(term, type: :observed_freq)
	end


	# Calculates frequencies of stored profiles terms
	# Params:
	# +ratio+:: if true, frequencies will be returned as ratios between 0 and 1.
	# +literal+:: if true, literal terms will be used to calculate frequencies instead translate alternative terms
	# +asArray+:: used to transform returned structure format from hash of Term-Frequency to an array of tuples [Term, Frequency]
	# +translate+:: if true, term IDs will be translated to 
	# Returns :: stored profiles terms frequencies
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
	# Params:
	# +prof+:: array of terms to be checked
	# Returns two arrays, first is the cleaned profile and second is the removed elements array
	def remove_ancestors_from_profile(prof)
		ancestors = prof.map{|term| self.get_ancestors(term)}.flatten.uniq
		redundant = prof.select{|term| ancestors.include?(term)}
		return prof - redundant, redundant
	end


	# Remove alternative IDs if official ID is present. DOES NOT REMOVE synonyms or alternative IDs of the same official ID
	# Params:
	# +prof+:: array of terms to be checked
	# Returns two arrays, first is the cleaned profile and second is the removed elements array
	def remove_alternatives_from_profile(prof)
		alternatives = prof.select{|term| @alternatives_index.include?(term)}
		redundant = alternatives.select{|alt_id| prof.include?(@alternatives_index[alt_id])}
		return prof - redundant, redundant
	end


	# Remove alternatives (if official term is present) and ancestors terms of a given profile 
	# Params:
	# +profile+:: profile to be cleaned
	# Returns :: cleaned profile
	def clean_profile(profile)
		terms_without_ancestors, _ = self.remove_ancestors_from_profile(profile)
		terms_without_ancestors_and_alternatices, _ = self.remove_alternatives_from_profile(terms_without_ancestors)
		return terms_without_ancestors_and_alternatices
	end


	# Remove alternatives (if official term is present) and ancestors terms of stored profiles 
	# Params:
	# +store+:: if true, clenaed profiles will replace already stored profiles
	# Returns a hash with cleaned profiles
	def clean_profiles(store: false)
		cleaned_profiles = {}
		@profiles.each{ |id, terms| cleaned_profiles[id] = self.clean_profile(terms)}
		@profiles = cleaned_profiles if store
		return cleaned_profiles
	end


	# Calculates number of ancestors present (redundant) in each profile stored
	# Returns :: array of parentals for each profile
	def parentals_per_profile
		cleaned_profiles = self.clean_profiles
		parentals = @profiles.each{ |id, terms| terms.length - cleaned_profiles[id].length}
		return parentals
	end


	#  Calculates mean IC of a given profile
	# Params:
	# +prof+:: profile to be checked
	# +ic_type+:: ic_type to be used
	# +zhou_k+:: special coeficient for Zhou IC method
	# Returns :: mean IC for a given profile
	def get_profile_mean_IC(prof, ic_type: :resnick, zhou_k: 0.5)
		return prof.map{|term| self.get_IC(term, type: ic_type, zhou_k: zhou_k)}.inject(0){|sum,x| sum + x}.fdiv(prof.length)
	end	


	# Calculates resnick ontology, and resnick observed mean ICs for all profiles stored
	# Returns :: two hashes with Profiles and IC calculated for resnick and observed resnick respectively
	def get_profiles_resnick_dual_ICs
		struct_ics = {}
		observ_ics = {}
		@profiles.each do |id, terms|
			struct_ics[id] = self.get_profile_mean_IC(terms, ic_type: :resnick)
			observ_ics[id] = self.get_profile_mean_IC(terms, ic_type: :resnick_observed)
		end
		return struct_ics.clone, observ_ics.clone
	end	


	# Calculates ontology structural levels for all ontology terms
	# Params:
	# ++::
	# Returns 
	def calc_term_levels
		if @meta.empty?
			warn('Terms metainfo are not already loaded. Aborting dictionary calc') 
		else
			byTerm = {}
			byValue = {}
			# Calc per term
			@meta.each do |term, info|
				level = info[:ancestors].round(0)
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


	# Return ontology levels calculated
	# Returns :: ontology levels calculated
	def get_ontology_levels
		return @dicts[:level][:byTerm] # By term, in this case, is Key::Level, Value::Terms
	end


	# Return ontology levels from profile terms
	# Returns :: hash of term levels (Key: level; Value: array of term IDs)
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
	# Returns :: void
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


	# Return :: profiles dictionary (clone)
	def get_terms_linked_profiles
		return @profilesDict.clone
	end	


	# Get related profiles to a given term
	# Params:
	# +term+:: to be checked
	# Returns :: profiles which contains given term
	def get_term_linked_profiles(term)
		return @profilesDict[term]
	end


	# Returns metainfo table from a set of terms
	# Params:
	# +terms+:: IDs to be expanded
	# +filter_alternatives+:: flag to be used in get_descendants method
	# Returns :: an array with triplets [TermID, TermName, DescendantsNames]
	def get_childs_table(terms, filter_alternatives = false)
		expanded_terms = []
		terms.each do |t|
			expanded_terms << [[t, self.translate_id(t)], self.get_descendants(t, filter_alternatives).map{|child| [child, self.translate_id(child)]}]
		end
		return expanded_terms
	end


	# Method used to store a pull of profiles
	# Params:
	# +profiles+:: array/hash of profiles to be stored. If it's an array, numerical IDs will be assigned starting at 1 
	# +calc_metadata+:: if true, launch calc_profiles_dictionary process
	# Returns :: void
	def load_profiles(profiles, calc_metadata: true) # TODO: refactor to use add_profile()
		# Check
		mergeable_profiles = {}
		if profiles.kind_of? Array
			profiles.each_with_index do |items, i|
				mergeable_profiles[i] = items.map {|item| item.to_sym}
			end
		elsif !profiles.keys.select{|id| @profiles.include?(id)}.empty? # Assume that !Array => isHash
			warn('Some profiles given are already stored. Stored version will be replaced')
		else
			mergeable_profiles = profiles			
		end
		@profiles.merge!(mergeable_profiles) # Merge
		mergeable_profiles.each{ |k,v| self.add_observed_terms(terms: v)} # Update

		if calc_metadata
			self.calc_profiles_dictionary
		end
	end


	# Store specific relations hash given into ITEMS structure
	# Params:
	# +relations+:: to be stored
	# +remove_old_relations+:: substitute ITEMS structure instead of merge new relations
	# Returns :: void
	def load_item_relations_to_terms(relations, remove_old_relations = false)
		@items = {} if remove_old_relations
		if !relations.select{|term, items| !@stanzas[:terms].include?(term)}.empty?
			warn('Some terms specified are not stored into this ontology. These not correct terms will be stored too')
		end
		if !remove_old_relations
			if !relations.select{|term, items| @items.include?(term)}.empty?
				warn('Some terms given are already stored. Stored version will be replaced')
			end
		end
		@items.merge!(relations)
	end	


	# NO IDEA WHAT THIS DOES. DON'T USE THIS METHODS IS NOT CHECKED
	# Params:
	# ++::
	# Returns
	def compute_relations_to_items(external_item_list, mode, thresold)
		results = []
		penalized_terms = {}
		terms_levels = get_terms_levels(@items_relations.keys)
		levels = terms_levels.keys.sort
		levels.reverse_each do |level|
			terms_levels[level].each do |term|
				associated_items = @items_relations[term]
				if mode == :elim 
					items_to_remove = penalized_terms[term]
					items_to_remove = [] if items_to_remove.nil?
					pval = get_fisher_exact_test(
						external_item_list - items_to_remove, 
						associated_items - items_to_remove, 
						((associated_items | external_item_list) - items_to_remove).length
						)
					if pval <= thresold
						parents = get_parents(term) # Save the items for each parent term to remove them later in the fisher test
						parents.each do |prnt|
							query = penalized_terms[prnt]
							if query.nil?
								penalized_terms[prnt] = @items_relations[term].clone # We need a new array to store the following iterations
							else
								query.concat(@items_relations[term])
							end
						end
					end
				end
				results << [term, pval]
			end
		end
		return results
	end


	# Check if a given ID is a removable (blacklist) term
	# Params:
	# +id+:: to be checked
	# Returns :: true if given term is a removable (blacklist) term or false in other cases
	def is_removable(id)
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
		# self.special_tags == other.special_tags &&
		self.max_freqs == other.max_freqs
    end

	
	#############################################
	# ACCESS CONTROL
	#############################################
	## ATTRIBUTES
	attr_reader :file, :header, :stanzas, :ancestors_index, :special_tags, :alternatives_index, :obsoletes_index, :structureType, :ics, :max_freqs, :meta, :dicts, :profiles, :profilesDict, :items, :removable_terms

end