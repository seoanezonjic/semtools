#! /usr/bin/env ruby

# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description class to test Similitude features


#########################################################
# Load necessary packages
#########################################################

ROOT_FOLDER = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_FOLDER, '..', 'lib', 'semtools'))
#$: << File.expand_path(File.join(ROOT_FOLDER, '../lib'))
AUX_FOLDER = File.join(ROOT_FOLDER, 'aux_files')

# require 'test/unit'
require 'minitest/autorun'
require 'obo_handler'

RubyVM::InstructionSequence.compile_option = {
  :tailcall_optimization => true,
  :trace_instruction => false
}


#########################################################
# Define TESTS
#########################################################
# class TestSimilitudes < Test::Unit::TestCase
class TestOBOFunctionalities < Minitest::Test

	def setup
		# Files
		@File_Header = {file: File.join(AUX_FOLDER, "only_header_sample.obo"), name: "only_header_sample"}
		@File_Hierarchical = {file: File.join(AUX_FOLDER, "hierarchical_sample.obo"), name: "hierarchical_sample"}
		@File_Circular = {file: File.join(AUX_FOLDER, "circular_sample.obo"), name: "circular_sample"}
		@File_Atomic = {file: File.join(AUX_FOLDER, "sparse_sample.obo"), name: "sparse_sample"}
		@File_Sparse = {file: File.join(AUX_FOLDER, "sparse2_sample.obo"), name: "sparse2_sample"}

		## OBO INFO
		@Load_Header = [{:file=>"test/aux_files/only_header_sample.obo", :name=>"only_header_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{}, :typedefs=>{}, :instances=>{}}]
		@Load_Hierarchical = [{:file=>"test/aux_files/hierarchical_sample.obo", :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>"Parental", :name=>"All", :comment=>"none"}, :Child1=>{:id=>"Child1", :name=>"Child1", :is_a=>"Parental ! Parental"}, :Child2=>{:id=>"Child2", :name=>"Child2", :alt_id=>"Child3", :is_a=>"Parental ! Parental"}}, :typedefs=>{}, :instances=>{}}]
		@Load_Circular = [{:file=>"test/aux_files/circular_sample.obo", :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>"A", :name=>"All", :is_a=>"C ! C"}, :B=>{:id=>"B", :name=>"B", :is_a=>"A ! A"}, :C=>{:id=>"C", :name=>"C", :is_a=>"B ! B"}}, :typedefs=>{}, :instances=>{}}]
		@Load_Atomic = [{:file=>"test/aux_files/sparse_sample.obo", :name=>"sparse_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>"Parental", :name=>"All", :comment=>"none"}, :Child1=>{:id=>"Child1", :name=>"Child1"}, :Child2=>{:id=>"Child2", :name=>"Child2"}}, :typedefs=>{}, :instances=>{}}]
		@Load_Sparse = [{:file=>"test/aux_files/sparse2_sample.obo", :name=>"sparse2_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>"A", :name=>"All"}, :B=>{:id=>"B", :name=>"B", :is_a=>"A ! A"}, :C=>{:id=>"C", :name=>"C", :is_a=>"A ! A"}, :D=>{:id=>"D", :name=>"Sparsed"}}, :typedefs=>{}, :instances=>{}}]

		# Parentals
		@Parentals_Hierachical = [:hierarchical, {:Child1=>[:Parental], :Child2=>[:Parental]}]
		@Parentals_Circular = [:circular, {:A=>[:C, :B], :C=>[:B, :A], :B=>[:A, :C]}]
		@Parentals_Atomic = [:atomic, {}]
		@Parentals_Sparse = [:sparse, {:B=>[:A], :C=>[:A]}]

		# Aux variables
		@Basic_tags = {:ancestors => [:is_a], :obsolete => [:is_obsolete], :alternative => [:alt_id,:replaced_by,:consider]}
		@Empty_ICs = {:resnick=>{}, :resnick_custom=>{}, :seco=>{}, :zhou=>{}, :sanchez=>{}}
		@Erroneous_freq = {:struct_freq=>-1.0, :custom_freq=>-1.0, :max_depth=>-1.0}
		@Empty_file = {:file=>nil, :name=>nil}

		# Create necessary instnaces
		@empty = OBO_Handler.new()
		@header = OBO_Handler.new(file: @File_Header[:file],load: true, expand_base: true)
		@hierarchical = OBO_Handler.new(file: @File_Hierarchical[:file],load: true, expand_base: true)
		@circular = OBO_Handler.new(file: @File_Circular[:file],load: true, expand_base: true)
		@atomic = OBO_Handler.new(file: @File_Atomic[:file],load: true, expand_base: true)
		@sparse = OBO_Handler.new(file: @File_Sparse[:file],load: true, expand_base: true)

		# Freqs variables
		@Hierarchical_freqs_default = {:struct_freq=>4.0, :custom_freq=>-1.0, :max_depth=>3.0}
		@Hierarchical_freqs_updated = {:struct_freq=>4.0, :custom_freq=> 2.0, :max_depth=>3.0}
	end

	#################################
	# INIT AND CLASS FUNCTIONALITIES
	#################################

	def test_transform_funcs
		## INFO2HASH
		assert_nil(OBO_Handler.info2hash(info: nil)) # Nil
		assert_nil(OBO_Handler.info2hash(info: "")) # Not an array
		assert_nil(OBO_Handler.info2hash(info: [])) # Empty array
		assert_raises RuntimeError do OBO_Handler.info2hash(info: [""]) end # Empty string
		assert_raises TypeError do OBO_Handler.info2hash(info: [8]) end # Not a string
		assert_raises TypeError do OBO_Handler.info2hash(info: [nil]) end # Nil element
		assert_raises EncodingError do OBO_Handler.info2hash(info: ["ab"]) end # Not correct format
		assert_equal({:a=>"b"},OBO_Handler.info2hash(info: ["a:b"])) # Correct format with one instance
		assert_equal({:a=>"b",:b=>"c"},OBO_Handler.info2hash(info: ["a:b","b:c"])) # Correct format with several instances (not overlapping)
		assert_equal({:a=>["b","c"]},OBO_Handler.info2hash(info: ["a:b","a:c"])) # Correct format with several instances (overlapping)
		assert_raises EncodingError do OBO_Handler.info2hash(info: ["a:b","ab"]) end # Several instances with some incorrect elements
	end

	def test_load_file
		assert_nil(OBO_Handler.load_obo(file: nil)) # Nil
		assert_nil(OBO_Handler.load_obo(file: 8)) # Not a string
		assert_nil(OBO_Handler.load_obo(file: "")) # Empty file
		assert_raises Errno::ENOENT do OBO_Handler.load_obo(file: "./.rb") end # Erroneous file path
		assert_equal(@Load_Header,OBO_Handler.load_obo(file: @File_Header[:file])) # Only header
		assert_equal(@Load_Hierarchical,OBO_Handler.load_obo(file: @File_Hierarchical[:file])) # Hierarchical
		assert_equal(@Load_Circular,OBO_Handler.load_obo(file: @File_Circular[:file])) # Circular
		assert_equal(@Load_Atomic,OBO_Handler.load_obo(file: @File_Atomic[:file])) # Sparsed
		assert_equal(@Load_Sparse,OBO_Handler.load_obo(file: @File_Sparse[:file])) # Sparsed 2
	end

	def test_init_obj
		assert_instance_of(OBO_Handler,OBO_Handler.new()) # Init without file
		assert_instance_of(OBO_Handler,OBO_Handler.new(file: nil)) # Init with nill
		assert_instance_of(OBO_Handler,OBO_Handler.new(file: @File_Header[:file])) # Init with file but without read
		assert_instance_of(OBO_Handler,OBO_Handler.new(file: @File_Header[:file],load: true)) # Init with file and launch read file
	end

	def test_expand
		assert_nil(OBO_Handler.expand_by_tag(terms: nil,target_tag: "")) # Nil terms
		assert_nil(OBO_Handler.expand_by_tag(terms: {},target_tag: "")) # Empty terms
		assert_nil(OBO_Handler.expand_by_tag(terms: [],target_tag: "")) # Terms not a hash
		assert_nil(OBO_Handler.expand_by_tag(terms: @Load_Hierarchical[2][:terms],target_tag: nil)) # Nil target
		assert_nil(OBO_Handler.expand_by_tag(terms: @Load_Hierarchical[2][:terms],target_tag: "")) # No/Empty target
		assert_nil(OBO_Handler.expand_by_tag(terms: @Load_Hierarchical[2][:terms],target_tag: 8)) # Target not a string
		assert_raises ArgumentError do OBO_Handler.expand_by_tag(@Load_Hierarchical[2][:terms],:is_a," ! ",split_info_indx=-1) end # Erroneous info_indx
		assert_raises TypeError do OBO_Handler.expand_by_tag(terms: {:A=>[1,2]},target_tag: :is_a) end # Terms without correct format {id, {tags}}
		assert_equal(@Parentals_Hierachical,OBO_Handler.expand_by_tag(terms: @Load_Hierarchical[2][:terms],target_tag: :is_a)) # Hierarchical structure
		assert_equal(@Parentals_Circular,OBO_Handler.expand_by_tag(terms: @Load_Circular[2][:terms],target_tag: :is_a)) # Circular structure
		assert_equal(@Parentals_Atomic,OBO_Handler.expand_by_tag(terms: @Load_Atomic[2][:terms],target_tag: :is_a)) # Sparse structure
		assert_equal(@Parentals_Sparse,OBO_Handler.expand_by_tag(terms: @Load_Sparse[2][:terms],target_tag: :is_a)) # Sparse structure with some other structures
	end


	#################################
	# ACCESSIONS
	#################################

	def test_read_write_variables
		# Generate dummy object
		dummy = OBO_Handler.new
		## @structureType (R)
		assert_nil(dummy.structureType)
		assert_raises NoMethodError do dummy.structureType = "A" end
		## @header (R)
		assert_nil(dummy.header)
		assert_raises NoMethodError do dummy.header = "A" end
		## @stanzas (R)
		assert_equal(@Load_Header[2],dummy.stanzas)
		assert_raises NoMethodError do dummy.stanzas = "A" end
		## @ancestors (R)
		assert_equal({},dummy.ancestors)
		assert_raises NoMethodError do dummy.ancestors = "A" end
		# => @alternatives :: has of alternative IDs (includee alt_id and obsoletes)
		assert_equal({},dummy.alternatives)
		assert_raises NoMethodError do dummy.alternatives = "A" end
		## @obsoletes (R)
		assert_equal({},dummy.obsoletes)
		assert_raises NoMethodError do dummy.obsoletes = "A" end
		## @special_tags (R)
		assert_equal(@Basic_tags,dummy.special_tags)
		assert_raises NoMethodError do dummy.special_tags = "A" end
		## @ics (R)
		assert_equal(@Empty_ICs,dummy.ics)
		assert_raises NoMethodError do dummy.ics = "A" end
		## @meta (R)
		assert_equal({},dummy.meta)
		assert_raises NoMethodError do dummy.meta = "A" end
		## @max_freqs (R)
		assert_equal(@Erroneous_freq,dummy.max_freqs)
		assert_raises NoMethodError do dummy.max_freqs = "A" end
	end


	#################################
	# SPECIAL TAGS FUNCTIONALITIES
	#################################

	def test_load
		# Instantiate necessary objects
		empty = OBO_Handler.new()
		header = OBO_Handler.new(file: @File_Header[:file])
		hierarchical = OBO_Handler.new(file: @File_Hierarchical[:file])
		circular = OBO_Handler.new(file: @File_Circular[:file])
		atomic = OBO_Handler.new(file: @File_Atomic[:file])
		sparse = OBO_Handler.new(file: @File_Sparse[:file])
		
		## Check loads
		assert_equal(false,@empty.load())
		assert_equal(true,@header.load())
		assert_equal(true,@hierarchical.load())
		assert_equal(true,@circular.load())
		assert_equal(true,@atomic.load())
		assert_equal(true,@sparse.load())

		## Check info
		# File
		assert_equal({},@empty.file)
		assert_equal(@File_Header,@header.file)
		assert_equal(@File_Hierarchical,@hierarchical.file)
		assert_equal(@File_Circular,@circular.file)
		assert_equal(@File_Atomic,@atomic.file)
		assert_equal(@File_Sparse,@sparse.file)
		# Header
		assert_nil(@empty.header)
		assert_equal(@Load_Header[1],@header.header)
		assert_equal(@Load_Hierarchical[1],@hierarchical.header)
		assert_equal(@Load_Circular[1],@circular.header)
		assert_equal(@Load_Atomic[1],@atomic.header)		
		assert_equal(@Load_Sparse[1],@sparse.header)		
		# Stanzas
		assert_equal(@Load_Header[2],@header.stanzas)
		assert_equal(@Load_Hierarchical[2],@hierarchical.stanzas)
		assert_equal(@Load_Circular[2],@circular.stanzas)
		assert_equal(@Load_Atomic[2],@atomic.stanzas)		
		assert_equal(@Load_Sparse[2],@sparse.stanzas)		
	end

	def test_obj_parentals
		# Instantiate
		empty = OBO_Handler.new()
		header = OBO_Handler.new(file: @File_Header[:file],load: true)
		hierarchical = OBO_Handler.new(file: @File_Hierarchical[:file],load: true)
		circular = OBO_Handler.new(file: @File_Circular[:file],load: true)
		atomic = OBO_Handler.new(file: @File_Atomic[:file],load: true)
		sparse = OBO_Handler.new(file: @File_Sparse[:file],load: true)

		assert_equal(false,empty.expand_parentals) # Empty
		assert_equal(false,header.expand_parentals) # Only header
		assert_equal(true,hierarchical.expand_parentals) # Hierarchical
		assert_equal(true,circular.expand_parentals) # Circular
		assert_equal(true,atomic.expand_parentals) # Atomic
		assert_equal(true,sparse.expand_parentals) # Sparse
	end

	def test_frequencies
		# Check freqs
		assert_equal(@Erroneous_freq,@empty.max_freqs) # Default freqs
		assert_equal(@Hierarchical_freqs_default,@hierarchical.max_freqs) # Only structural freq
		# Update hierarchical custom freq
		@hierarchical.add_observed_terms(terms: ["Child2","Child2"], to_Sym: true)
		# Check custom freq
		assert_equal(@Hierarchical_freqs_updated,@hierarchical.max_freqs) # Only structural freq
	end


	def test_special_loads
		# Instantiate
		# obsoletes
		# alternative ids
		# expansions
	end


	

	#################################
	# METADATA FUNCTIONALITIES
	#################################


end
