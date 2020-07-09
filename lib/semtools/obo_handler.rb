#########################################################
# AUTHOR NOTES
#########################################################

# 1 - Handle "consider" values
# 2 - Handle custom freqs into ICs

class OBO_Handler
	#############################################
	# FIELDS
	#############################################
	# Handled class variables
	# => @@basic_tags :: hash with main OBO structure tags
	# => @@allowed_calcs :: hash with allowed ICs and similaritites calcs
	#
	# Handled object variables
	# => @file :: handled OBO file. Stored info {:file,:name}
	# => @header :: file header (if is available)
	# => @stanzas :: OBO stanzas {:terms,:typedefs,:instances}
	# => @ancestors :: hash of ancestors/descendants per each term handled with any structure relationships
	# => @alternatives :: has of alternative IDs (includee alt_id and obsoletes)
	# => @obsoletes :: hash of obsoletes and it's new ids
	# => @special_tags :: set of special tags to be expanded (:is_a, :obsolete, :alt_id)
	# => @structureType :: type of ontology structure depending on ancestors relationship. Allowed: {atomic, sparse, circular, hierarchical}
	# => @ics :: already calculated ICs for handled terms and IC types
	# => @meta :: meta_information about handled terms like [ancestors, descendants, struct_freq, custom_freq]
	# => @max_freqs :: maximum freqs found for structural and custom freqs

	@@basic_tags = {ancestors: [:is_a], obsolete: [:is_obsolete], alternative: [:alt_id,:replaced_by,:consider]}
	@@allowed_calcs = {ics: [:resnick,:resnick_custom,:seco,:zhou,:sanchez], sims: [:resnick,:lin,:jiang_conrath]}

	#############################################
	# CONSTRUCTOR
	#############################################
	def initialize(file: nil, load: false, expand_base: false)
		# Initialize object variables
		@file = file.nil? ? {} : {file: file, name: File.basename(file,File.extname(file))}
		@header = nil
		@stanzas = {terms: {}, typedefs: {}, instances: {}}
		@ancestors = {}
		@alternatives = {}
		@obsoletes = {}
		@structureType = nil
		@ics = {@@allowed_calcs[:ics].map{|ictype| [ictype, {}]}}
		@meta = {}
		@special_tags = @@basic_tags.clone
		@max_freqs = {:struct_freq => -1.0, :custom_freq => -1.0, :max_depth => -1.0}

		load() if load
		expand_base() if expand_base
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
	# Note: we extremly recomend use expand_by_tag function instead of it (directly)
	def self.expand_tag(start,terms,target_tag,expansion = {}, split_info_char = " ! ", split_info_indx = 0, alt_ids = {})
		# Check
		return nil if start.nil?
		return nil if terms.nil?
		return nil if !terms.is_a? Hash
		return nil if terms.length <= 0
		return nil if target_tag.nil?
		return nil if !target_tag.is_a? Symbol
		return nil if target_tag.length <= 0
		return nil if expansion.nil?
		raise ArgumentError, 'Info_index can not be a negative number' if split_info_indx < 0
		# Take start term available info and already accumulated info
		current_expanded = expansion[start].nil? ? [] : expansion[start]
		start_expansion = terms[start][target_tag]
		return [:source,[]] if start_expansion.nil?
		start_expansion = start_expansion.clone
		start_expansion = Array.new(1,start_expansion) unless start_expansion.kind_of?(Array)

		# Prepare auxiliar variables
		visited = []
		struc = :hierarchical

		# Study direct extensions
		while start_expansion.length > 0
			# Take current element
			id = start_expansion.shift
			id = id.split(split_info_char)[split_info_indx]	
			id = id.to_sym
			id = alt_ids[id] if alt_ids.include? id # NOTE: if you want to persist current ID instead source ID, re-implement this
			# Handle
			if current_expanded.include? id # Check if already have been included into this expansion
				struct = :circular 
			elsif expansion.include? id # Check if current already has been expanded
				# Concat
				current_expanded << id 
				current_expanded = current_expanded | expansion[id]
				# Check circular case
				if current_expanded.include? start
					struct = :circular
					[id,start].each do |repeated| current_expanded.delete(repeated) end
				end	
			else # Expand
				# Add current
				current_expanded << id
				expansion[start] = current_expanded
				# Expand current
				structExp, expansionNew = OBO_Handler.send :expand_tag,id,terms,target_tag,expansion,split_info_char,split_info_indx,alt_ids
				# Concat
				current_expanded = current_expanded | expansionNew unless expansionNew.nil?
				# Check struct
				struct = :circular if structExp == :circular
				# Check circular case
				if (current_expanded.include? start)
					struct = :circular
					current_expanded.delete(start)
				end
			end
		end

		# Update
		expansion[start] = current_expanded

		# Return
		return struct, current_expanded
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
	def self.expand_by_tag(terms:,target_tag:, split_info_char: " ! ", split_info_indx: 0, alt_ids: {}, obsoletes: 0)
		# Check special cases
		return nil if terms.nil?
		return nil if !terms.is_a? Hash
		return nil if terms.length <= 0
		return nil if target_tag.nil?
		return nil if !target_tag.is_a? Symbol
		return nil if target_tag.length <= 0
		raise ArgumentError, 'Info_index can not be a negative number' if split_info_indx < 0

		# Define structure type
		structType = :hierarchical
		expansion = {}
		terms.each do |id,tags|
			# Check
			next if tags.nil?
			raise TypeError, 'Tags of term (#{id}) is not a hash' unless tags.is_a? Hash 
			# Check if target tag is defined
			if tags.keys.include? target_tag
				# id = id.split(split_info_char)[split_info_indx]
				# Obtain related terms
				set_structure, related_ids = OBO_Handler.send :expand_tag, id, terms, target_tag, expansion, split_info_char, split_info_indx, alt_ids
				# Check structure
				if(set_structure == :circular)
					structType = :circular
				end
				# Update Expansion info
				expansion[id] = related_ids
			end
		end

		# Check special case
		structType = :atomic if expansion.length <= 0
		structType = :sparse if (expansion.length > 0) & ((terms.length - expansion.length - obsoletes) >= 2)
		# Return type and hash with expansion
		return structType, expansion
	end


	# Class method to transform string with <tag : info> into hash structure
	# Param:
	# +info+:: string with info to be transformed into hash format
	# Return info stored into hash structure
	def self.info2hash(info:)
		# Check special cases
		return nil if info.nil?
		return nil if !info.is_a? Array
		return nil if info.length <= 0
		# Load info
		info_hash = {}
		info.each do |tag_tuple|
			# Check special cases
			raise TypeError, 'Info element is NIL' if tag_tuple.nil?
			raise TypeError, 'Info element is not a string' if !tag_tuple.is_a? String
			raise 'Info element is empty string' if tag_tuple.length <= 0
			# Split info
			tag, value = tag_tuple.split(':',2)
			# Check
			raise EncodingError, 'Info element incorrect format' if (tag.nil?) | (value.nil?)
			# Prepare
			tag.lstrip!
			tag = tag.to_sym
			value.lstrip!
			# Store
			if info_hash.keys.include? tag
				if !info_hash[tag].kind_of?(Array)
					info_hash[tag] = [info_hash[tag]]
				end
				info_hash[tag] << value				
			else
				info_hash[tag] = value
			end
		end
		return info_hash
	end


	# Class method to load an OBO format file (based on OBO 1.4 format). Specially focused on load
	# the Header, the Terms, the Typedefs and the Instances.
	# Param:
	# +file+:: OBO file to be loaded
	# Returns hash with FILE, HEADER and STANZAS info
	def self.load_obo(file:)
		# Check special cases
		return nil if file.nil?
		return nil if !file.is_a? String
		return nil if file.length <= 0

		# Data variables
		header = ""
		terms = {}
		typedefs = {}
		instances = {}
		# Auxiliar variables
		infoType = "Header"
		currInfo = []
		stanzas = ["[Term]","[Typedef]","[Instance]"]
		# Read file
		File.open(file).each do |line|
			line.chomp!
			# Check if new instance is found
			if stanzas.include? line
				currInfo = self.info2hash(info: currInfo)
				id = currInfo.first[1].to_sym
				# Store current info
				case infoType
				when "Header" 
					header = currInfo
				when "Term"
					terms[id] = currInfo
				when "Typedef"
					typedefs[id] = currInfo
				when "Instance"
					instances[id] = currInfo
				end
				# Update info variables
				currInfo = []
				infoType = line.gsub!(/["\[\]"]/,"")
				next
			end
			# Concat info
			currInfo << line unless line.length <= 0
		end
		# Store last loaded info
		if currInfo.length > 0
			currInfo = self.info2hash(info: currInfo)
			id = currInfo.first[1].to_sym
			# Store current info
			case infoType
			when "Header" 
				header = currInfo
			when "Term"
				terms[id] = currInfo
			when "Typedef"
				typedefs[id] = currInfo
			when "Instance"
				instances[id] = currInfo
			end
		end

		# Prepare to return
		finfo = {:file => file, :name => File.basename(file,File.extname(file))}
		stanzas = {:terms => terms, :typedefs => typedefs, :instances => instances}
		return finfo, header, stanzas
		# return {"Header" => header, "Term" => terms, "Typedef" => typedefs, "Instance" => instances}
	end


	#############################################
	# GENERAL METHODS
	#############################################
	
	def add_observed_term(term:,increase: 1.0)
		# Check
		raise ArgumentError, "Term given is NIL" if term.nil?
		return false unless @stanzas[:terms].keys.include? term
	
		# Check if exists
		@meta[term] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:custom_freq => -1.0} if @meta[term].nil?
		# Add frequency
		@meta[term][:custom_freq] = 0 if @meta[term][:custom_freq] == -1
		@meta[term][:custom_freq] += increase
		# Check maximum frequency
		@max_freqs[:custom_freq] = @meta[term][:custom_freq] if @max_freqs[:custom_freq] < @meta[term][:custom_freq]  
		return true
	end


	# Increase the arbitrary frequency of a given term set 
	# Params:
	# +terms+:: set of terms to be updated
	# +increase+:: amount to be increased
	# Returns true if process ends without errors and false in other cases
	def add_observed_terms(terms:, increase: 1.0, to_Sym: false)
		# Check
		raise ArgumentError, 'Terms array given is NIL' if terms.nil?
		raise ArgumentError, 'Terms given is not an array' if !terms.is_a? Array
		# Add observations
		if to_Sym
			checks = terms.map{|id| self.add_observed_term(term: id.to_sym,increase: increase)}
		else
			checks = terms.map{|id| self.add_observed_term(term: id,increase: increase)}
		end
		return checks
	end



	#
	#
	#
	# 
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
	def expand_alternatives(alt_tag: @@basic_tags[:alternative][0])
		# Check input
		return false if @stanzas[:terms].empty?
		# Take all alternative IDs
		terms_copy = @stanzas[:terms].keys
		terms_copy.each do |id|
			tags = @stanzas[:terms][id]
			next if tags.nil?
			if tags.keys.include? alt_tag
				# Check alternative ids
				alt_ids = tags[alt_tag]
				alt_ids = Array.new(1,alt_ids) if !alt_ids.kind_of? Array
				# Update info
				alt_ids.each do |alt_term|
					alt_term = alt_term.to_sym
					@alternatives[alt_term] = id
					@stanzas[:terms][alt_term] = @stanzas[:terms][id] if !@stanzas[:terms].include? alt_term
					if !@ancestors.nil?
						@ancestors[alt_term] = @ancestors[id] if @ancestors.include? id
					end
				end
			end
		end
		# Everything ok
		return true
	end


	# Executes basic expansions of tags (alternatives, obsoletes and parentals) with default values
	# Returns :: true if eprocess ends without errors and false in other cases
	def expand_base()
		a = self.expand_alternatives
		b = self.expand_obsoletes
		b = self.expand_obsoletes(alt: @@basic_tags[:alternative][2])
		c = self.expand_parentals
		d = self.expand_frequencies
		return a & b & c & d
	end


	# Calculates regular frequencies based on ontology structure (using parentals)
	# Returns :: true if everything end without errors and false in other cases
	def expand_frequencies()
		# Check
		return false if @ancestors.empty?
		# Reset
		@meta.each do |id, freqs|
			next if 
			freqs[:struct_freq] = 0
		end
		# Per each term, add frequencies
		@stanzas[:terms].each do |id, tags|
			# Check if exist
			@meta[id] = {:ancestors => -1.0,:descendants => -1.0,:struct_freq => 0.0,:custom_freq => -1.0} if @meta[id].nil?
			# Store metadata
			@meta[id][:ancestors] = (@ancestors.include? id) ? @ancestors[id][:ancestors].length.to_f : 0.0
			@meta[id][:descendants] = (@ancestors.include? id) ? @ancestors[id][:descendants].length.to_f : 0.0
			@meta[id][:struct_freq] = @meta[id][:descendants] + 1.0
			# Update maximums
			@max_freqs[:struct_freq] = @meta[id][:struct_freq] if @max_freqs[:struct_freq] < @meta[id][:struct_freq]  
			@max_freqs[:max_depth] = @meta[id][:descendants] if @max_freqs[:max_depth] < @meta[id][:descendants]  
		end
		return true
	end


	# Expand obsoletes set and link info to their alternative IDs
	# Params:
	# +obs_tag+:: tag to be used to find obsoletes
	# +alt+:: tag to find alternative IDs (if are available)
	# +reset_obsoletes+:: flag to indicate if obsoletes set must be reset. Default: true
	# Returns true if process ends without errors and false in other cases
	def expand_obsoletes(obs_tag: @@basic_tags[:obsolete][0], alt: @@basic_tags[:alternative][1], reset_obsoletes: true)
		# Check
		return false if @stanzas[:terms].empty?
		# Reset
		@obsoletes = {} if reset_obsoletes
		# Check obsoletes
		@stanzas[:terms].each do |id, tags|
			next if tags.nil?
			if tags.keys.include? obs_tag
				next if !@obsoletes[id].nil?
				@obsoletes[id] = nil
				# @alternatives[id] = nil
				# Check obsolete
				next if !tags[obs_tag]
				alt_id = nil
				# Check if alternative value is available
				alt_id = tags[alt] if tags.keys.include? alt
				next if alt_id.nil?
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
				# That is not a correct way to do this 
				alt_id = alt_id[0] if alt_id.kind_of? Array
# >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
				# Store
				@alternatives[id] = alt_id.to_sym
				@obsoletes[id] = alt_id.to_sym	
			end
		end
		# END
		return true
	end


	# Expand parentals set and link all info to their alternative IDs. Also launch frequencies process
	# Params:
	# +tag+:: tag used to expand parentals
	# +split_info_char+:: special regex used to split info (if it is necessary)
	# +split_info_indx+:: special index to take splitted info (if it is necessary)
	# Returns true if process ends without errors and false in other cases
	def expand_parentals(tag: @@basic_tags[:ancestors][0],split_info_char: " ! ", split_info_indx: 0)
		# Check
		return false if @stanzas[:terms].nil?
		# Expand
		structType, parentals = self.class.expand_by_tag(terms: @stanzas[:terms],
														target_tag: tag,
														split_info_char: split_info_char,
														split_info_indx: split_info_indx, 
														alt_ids: @alternatives,
														obsoletes: @obsoletes.length)
		# Check
		return false if (structType.nil?) | parentals.nil?
		# Prepare ancestors structure
		anc = {}
		parentals.each do |id, parents|
			# Store ancestors
			anc[id] = {:ancestors => [], :descendants => []} if !anc.include? id
			anc[id][:ancestors] = parents
			# Add descendants
			parents.each do |anc_id|
				anc[anc_id] = {:ancestors => [], :descendants => []} if !anc.include? anc_id
				anc[anc_id][:descendants] << id
			end
		end
		# Store alternatives
		@alternatives.each do |id,alt|
			# Store
			anc[id] = anc[alt] if anc.include? alt
			anc[id] = {:ancestors => [], :descendants => []} if anc[id].nil?
		end
		# Check structure
		if ![:atomic,:sparse].include? structureType
			structType = :hierarchical
			anc.map{|k,v| structType = :circular if (v[:ancestors].include? k) | (v[:descendants].include? k)}
		end
		# Store
		@ancestors = anc
		@structureType = structType
		# Finish		
		return true
	end


	# Find ancestors of a given term
	# Params:
	# +term+:: to be checked
	# Returns an array with all ancestors of given term or false if parents are not available yet
	def get_ancestors(term:)
		return self.get_familiar(term: term,return_ancestors: true)		
	end

	# Find descendants of a given term
	# Params:
	# +term+:: to be checked
	# Returns an array with all descendants of given term or false if parents are not available yet
	def get_descendants(term:)
		return self.get_familiar(term: term,return_ancestors: false)		
	end

	# Find ancestors/descendants of a given term
	# Params:
	# +term+:: to be checked
	# +return_ancestors+:: return ancestors if true or descendants if false
	# Returns an array with all ancestors/descendants of given term or false if parents are not available yet
	def get_familiar(term:, return_ancestors: true)
		# Check
		raise ArgumentError, 'Term specified is NIL' if term.nil?
		return false if @ancestors.nil?
		return false if @ancestors[term].nil?
		term = term.to_sym if term.is_a? String
		# Find into parentals
		return return_ancestors ? @ancestors[term][:ancestors] : @ancestors[term][:descendants]		
	end


	# 
	# Params:
	# +term+:: 
	# +type+::
	# +force+::
	# +zhou_k+::
	# Returns 
	def get_IC(term: ,type: :resnick, force: false, zhou_k: 0.5)
		# Check 
		raise ArgumentError, 'Term specified is NIL' if term.nil?
		raise ArgumentError, "IC type specified (#{type}) is not allowed" if !@@allowed_calcs[:ics].include? type
		term = term.to_sym if term.is_a? String
		# Check if it's already calculated
		return @ics[type][term] if (@ics[type].include? term) & !force
		# Calculate
		ic = - 1
		case type
			when :resnick
				# -log(Freq(x) / Max_Freq)
				ic = -Math.log10(@meta[term][:struct_freq].fdiv(@max_freqs[:struct_freq]))
			when :resnick_custom
				# -log(Freq(x) / Max_Freq)
				ic = -Math.log10(@meta[term][:custom_freq].fdiv(@max_freqs[:custom_freq]))
			when :seco
				#  1 - ( log(hypo(x) + 1) / log(max_nodes) )
				ic = 1 - Math.log10(@meta[term][:struct_freq]).fdiv(Math.log10(@stanzas[:terms].length - @alternatives.length))
			when :zhou
				# k*(IC_Seco(x)) + (1-k)*(log(depth(x))/log(max_depth)) 
				ic_seco = 1 - Math.log10(@meta[term][:struct_freq]).fdiv(Math.log10(@stanzas[:terms].length - @alternatives.length))
				ic = zhou_k * ic_seco + (1.0 - zhou_k) * (Math.log10(@meta[term][:descendants]).fdiv(Math.log10(@max_freqs[:max_depth])))
			when :sanchez
				ic = -Math.log10((@meta[term][:descendants].fdiv(@meta[term][:ancestors]) + 1.0).fdiv(@max_freqs[:max_depth] + 1.0))
		end			
		# Store
		@ics[type][term] = ic
		@ics[:seco][term] = ic_seco if type == :zhou
		# Return
		return ic
	end


	# Find the IC of the Most Index Content shared Ancestor (MICA) of two given terms
	# Params:
	# +termA+:: term to be cheked
	# +termB+:: term to be checked
	# +ic_type+:: IC formula to be used
	# Returns the IC of the MICA(termA,termB)
	def get_ICMICA(termA:,termB:,ic_type: :resnick)
		mica = self.get_MICA(termA: termA,termB: termB,ic_type: ic_type)
		return false if !mica
		return mica[1]
	end


	# Find the Most Index Content shared Ancestor (MICA) of two given terms
	# Params:
	# +termA+:: term to be cheked
	# +termB+:: term to be checked
	# +ic_type+:: IC formula to be used
	# Returns the MICA(termA,termB) and it's IC
	def get_MICA(termA:,termB:,ic_type: :resnick)
		# Obtain ancestors (include itselfs too)
		anc_A = self.get_ancestors(term: termA) | [termA]
		anc_B = self.get_ancestors(term: termB) | [termB]

		# Check
		return false if (!anc_A) | (!anc_B)
		# Find shared ancestors
		shared_ancestors = anc_A & anc_B
		# Find MICA
		mica = [nil,-1.0]
		return mica if shared_ancestors.length <= 0
		shared_ancestors.each do |anc|
			# Obtain IC
			ic = self.get_IC(term: anc, type: ic_type)
			# Check
			mica = [anc,ic] if ic > mica[1]
		end
		# Return value calculated
		return mica
	end


	# 
	# Params:
	# +termsA+:: to be compared
	# +termsB+:: to be compared
	# +type+:: similitude formula to be used
	# +ic_type+:: IC formula to be used
	# Returns the similarity between both sets or false if frequencies are not available yet
	def get_similarity(termA:, termB:, type: :resnick, ic_type: :resnick)
		# Check
		raise ArgumentError, 'Terms specified are NIL' if termA.nil? | termB.nil?
		raise ArgumentError, "IC type specified (#{ic_type}) is not allowed" if !@@allowed_calcs[:ics].include? ic_type
		raise ArgumentError, "SIM type specified (#{type}) is not allowed" if !@@allowed_calcs[:sims].include? type
		# Launch comparissons
		sim_res = get_ICMICA(termA: termA, termB: termB, ic_type: ic_type)
		case type
			when :resnick
				sim = sim_res
			when :lin
				sim = (2.0 * sim_res).fdiv(self.get_IC(term: termA,type: ic_type) + self.get_IC(term: termB,type: ic_type))
			when :jiang_conrath
				sim = (self.get_IC(term: termA,type: ic_type) + self.get_IC(term: termB,type: ic_type)) - (2.0 * sim_res)
		end
		# Return
		return sim
	end



	# Method used to load information stored into an OBO file and store it into this object.
	# If a file is specified by input parameter, current @file value is updated
	# Param
	# +file+:: optional file to update object stored file
	# Return true if process ends without errors, false in other cases
	def load(file: nil)
		# Check special cases
		file = @file[:file] if file.nil?
		return false if file.nil?
		# Load
		finfo, header, stanzas = self.class.load_obo(file: file)
		# Check special cases
		return false if finfo.nil?
		# Store
		@file = finfo
		@header = header
		@stanzas = stanzas

		# Return
		return true
	end
	
	#############################################
	# ACCESS CONTROL
	#############################################
	## METHODS
	# public :get_ancestors, :get_descendants, :get_familiar
	# private
	private_class_method :expand_tag

	## ATTRIBUTES
	attr_reader :file, :header, :stanzas, :ancestors, :special_tags, :alternatives, :obsoletes, :structureType, :ics, :max_freqs, :meta
	# attr_writer 

end