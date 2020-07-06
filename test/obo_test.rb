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
		@File_Header = File.join(AUX_FOLDER, "only_header_sample.obo")
		@File_Hierarchical = File.join(AUX_FOLDER, "hierarchical_sample.obo")
		@File_Circular = File.join(AUX_FOLDER, "circular_sample.obo")
		@File_Atomic = File.join(AUX_FOLDER, "sparse_sample.obo")
		@File_Sparse = File.join(AUX_FOLDER, "sparse2_sample.obo")

		## OBO INFO
		@Load_Header = {"Header"=>{"format-version"=>"1.2", "data-version"=>"test/a/b/c/"}, "Term"=>{}, "Typedef"=>{}, "Instance"=>{}}
		@Load_Hierarchical = {"Header"=>{"format-version"=>"1.2", "data-version"=>"test/a/b/c/"}, "Term"=>{"Parental"=>{"id"=>"Parental", "name"=>"All", "comment"=>"none"}, "Child1"=>{"id"=>"Child1", "name"=>"Child1", "is_a"=>"Parental ! Parental"}, "Child2"=>{"id"=>"Child2", "name"=>"Child2", "alt_id"=>"Child3", "is_a"=>"Parental ! Parental"}}, "Typedef"=>{}, "Instance"=>{}}
		@Load_Circular = {"Header"=>{"format-version"=>"1.2", "data-version"=>"test/a/b/c/"}, "Term"=>{"A"=>{"id"=>"A", "name"=>"All", "is_a"=>"C ! C"}, "B"=>{"id"=>"B", "name"=>"B", "is_a"=>"A ! A"}, "C"=>{"id"=>"C", "name"=>"C", "is_a"=>"B ! B"}}, "Typedef"=>{}, "Instance"=>{}}
		@Load_Atomic = {"Header"=>{"format-version"=>"1.2", "data-version"=>"test/a/b/c/"}, "Term"=>{"Parental"=>{"id"=>"Parental", "name"=>"All", "comment"=>"none"}, "Child1"=>{"id"=>"Child1", "name"=>"Child1"}, "Child2"=>{"id"=>"Child2", "name"=>"Child2"}}, "Typedef"=>{}, "Instance"=>{}}
		@Load_Sparse = {"Header"=>{"format-version"=>"1.2", "data-version"=>"test/a/b/c/"}, "Term"=>{"A"=>{"id"=>"A", "name"=>"All"}, "B"=>{"id"=>"B", "name"=>"B", "is_a"=>"A ! A"}, "C"=>{"id"=>"C", "name"=>"C", "is_a"=>"A ! A"}, "D"=>{"id"=>"D", "name"=>"Sparsed"}}, "Typedef"=>{}, "Instance"=>{}}

		# Parentals
		@Parentals_Hierachical = ["Hierarchical", {"Child1"=>["Parental"], "Child2"=>["Parental"]}]
		@Parentals_Circular = ["Circular", {"A"=>["C", "B"], "C"=>["B", "A"], "B"=>["A", "C"]}]
		@Parentals_Atomic = ["Atomic", {}]
		@Parentals_Sparse = ["Sparse", {"B"=>["A"], "C"=>["A"]}]
	end

	#################################
	# INIT AND CLASS FUNCTIONALITIES
	#################################

	def test_transform_funcs
		## INFO2HASH
		assert_nil(OBO_Handler.info2hash(nil)) # Nil
		assert_nil(OBO_Handler.info2hash("")) # Not an array
		assert_nil(OBO_Handler.info2hash([])) # Empty array
		assert_raises RuntimeError do OBO_Handler.info2hash([""]) end # Empty string
		assert_raises TypeError do OBO_Handler.info2hash([8]) end # Not a string
		assert_raises TypeError do OBO_Handler.info2hash([nil]) end # Nil element
		assert_raises EncodingError do OBO_Handler.info2hash(["ab"]) end # Not correct format
		assert_equal({"a"=>"b"},OBO_Handler.info2hash(["a:b"])) # Correct format with one instance
		assert_equal({"a"=>"b","b"=>"c"},OBO_Handler.info2hash(["a:b","b:c"])) # Correct format with several instances (not overlapping)
		assert_equal({"a"=>["b","c"]},OBO_Handler.info2hash(["a:b","a:c"])) # Correct format with several instances (overlapping)
		assert_raises EncodingError do OBO_Handler.info2hash(["a:b","ab"]) end # Several instances with some incorrect elements
	end

	def test_load_file
		assert_nil(OBO_Handler.load_obo(nil)) # Nil
		assert_nil(OBO_Handler.load_obo(8)) # Not a string
		assert_nil(OBO_Handler.load_obo("")) # Empty file
		assert_raises Errno::ENOENT do OBO_Handler.load_obo("./.rb") end # Erroneous file path
		assert_equal(@Load_Header,OBO_Handler.load_obo(@File_Header)) # Only header
		assert_equal(@Load_Hierarchical,OBO_Handler.load_obo(@File_Hierarchical)) # Hierarchical
		assert_equal(@Load_Circular,OBO_Handler.load_obo(@File_Circular)) # Circular
		assert_equal(@Load_Atomic,OBO_Handler.load_obo(@File_Atomic)) # Sparsed
		assert_equal(@Load_Sparse,OBO_Handler.load_obo(@File_Sparse)) # Sparsed 2
	end

	def test_init_obj
		assert_instance_of(OBO_Handler,OBO_Handler.new()) # Init without file
		assert_instance_of(OBO_Handler,OBO_Handler.new(nil)) # Init with nill
		assert_instance_of(OBO_Handler,OBO_Handler.new(@File_Header)) # Init with file but without read
		assert_instance_of(OBO_Handler,OBO_Handler.new(@File_Header,true)) # Init with file and launch read file
	end

	def test_expand
		assert_nil(OBO_Handler.expand_by_tag(nil,"")) # Nil terms
		assert_nil(OBO_Handler.expand_by_tag({},"")) # Empty terms
		assert_nil(OBO_Handler.expand_by_tag([],"")) # Terms not a hash
		assert_nil(OBO_Handler.expand_by_tag(@Load_Hierarchical["Term"],nil)) # Nil target
		assert_nil(OBO_Handler.expand_by_tag(@Load_Hierarchical["Term"],"")) # No/Empty target
		assert_nil(OBO_Handler.expand_by_tag(@Load_Hierarchical["Term"],8)) # Target not a string
		assert_raises ArgumentError do OBO_Handler.expand_by_tag(@Load_Hierarchical["Term"],"is_a"," ! ",split_info_indx=-1) end # Erroneous info_indx
		assert_raises TypeError do OBO_Handler.expand_by_tag({"A"=>[1,2]},"is_a") end # Terms without correct format {id, {tags}}
		assert_equal(@Parentals_Hierachical,OBO_Handler.expand_by_tag(@Load_Hierarchical["Term"],"is_a")) # Hierarchical structure
		assert_equal(@Parentals_Circular,OBO_Handler.expand_by_tag(@Load_Circular["Term"],"is_a")) # Circular structure
		assert_equal(@Parentals_Atomic,OBO_Handler.expand_by_tag(@Load_Atomic["Term"],"is_a")) # Sparse structure
		assert_equal(@Parentals_Sparse,OBO_Handler.expand_by_tag(@Load_Sparse["Term"],"is_a")) # Sparse structure with some other structures
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
		## @terms (R)
		assert_nil(dummy.terms)
		assert_raises NoMethodError do dummy.terms = "A" end
		## @typedefs (R)
		assert_nil(dummy.typedefs)
		assert_raises NoMethodError do dummy.typedefs = "A" end
		## @instances (R)
		assert_nil(dummy.instances)
		assert_raises NoMethodError do dummy.instances = "A" end
		## @parents (R)
		assert_nil(dummy.parents)
		assert_raises NoMethodError do dummy.parents = "A" end
		## @obsoletes (R)
		assert_nil(dummy.obsoletes)
		assert_raises NoMethodError do dummy.obsoletes = "A" end
		## @expansions (R)
		assert_equal({},dummy.expansions)
		assert_raises NoMethodError do dummy.expansions = "A" end
	end


	#################################
	# SPECIAL TAGS FUNCTIONALITIES
	#################################

	def test_load
		# Instantiate necessary objects
		empty = OBO_Handler.new()
		header = OBO_Handler.new(@File_Header)
		hierarchical = OBO_Handler.new(@File_Hierarchical)
		circular = OBO_Handler.new(@File_Circular)
		atomic = OBO_Handler.new(@File_Atomic)
		sparse = OBO_Handler.new(@File_Sparse)
		
		## Check loads
		assert_equal(false,empty.load())
		assert_equal(true,header.load())
		assert_equal(true,hierarchical.load())
		assert_equal(true,circular.load())
		assert_equal(true,atomic.load())
		assert_equal(true,sparse.load())

		## Check info
		# File
		assert_nil(empty.file)
		assert_equal(@File_Header,header.file)
		assert_equal(@File_Hierarchical,hierarchical.file)
		assert_equal(@File_Circular,circular.file)
		assert_equal(@File_Atomic,atomic.file)
		assert_equal(@File_Sparse,sparse.file)
		# Info
		assert_nil(empty.info)
		assert_equal(@Load_Header,header.info)
		assert_equal(@Load_Hierarchical,hierarchical.info)
		assert_equal(@Load_Circular,circular.info)
		assert_equal(@Load_Atomic,atomic.info)		
		assert_equal(@Load_Sparse,sparse.info)		
		# Header
		assert_nil(empty.header)
		assert_equal(@Load_Header["Header"],header.header)
		assert_equal(@Load_Hierarchical["Header"],hierarchical.header)
		assert_equal(@Load_Circular["Header"],circular.header)
		assert_equal(@Load_Atomic["Header"],atomic.header)		
		assert_equal(@Load_Sparse["Header"],sparse.header)		
		# Terms
		assert_nil(empty.terms)
		assert_equal(@Load_Header["Term"],header.terms)
		assert_equal(@Load_Hierarchical["Term"],hierarchical.terms)
		assert_equal(@Load_Circular["Term"],circular.terms)
		assert_equal(@Load_Atomic["Term"],atomic.terms)		
		assert_equal(@Load_Sparse["Term"],sparse.terms)		
		# Typedefs
		assert_nil(empty.typedefs)
		assert_equal(@Load_Header["Typedef"],header.typedefs)
		assert_equal(@Load_Hierarchical["Typedef"],hierarchical.typedefs)
		assert_equal(@Load_Circular["Typedef"],circular.typedefs)
		assert_equal(@Load_Atomic["Typedef"],atomic.typedefs)		
		assert_equal(@Load_Sparse["Typedef"],sparse.typedefs)		
		# Instances
		assert_nil(empty.instances)
		assert_equal(@Load_Header["Instance"],header.instances)
		assert_equal(@Load_Hierarchical["Instance"],hierarchical.instances)
		assert_equal(@Load_Circular["Instance"],circular.instances)
		assert_equal(@Load_Atomic["Instance"],atomic.instances)		
		assert_equal(@Load_Sparse["Instance"],sparse.instances)		
	end

	def test_obj_parentals
		# Instantiate
		empty = OBO_Handler.new()
		header = OBO_Handler.new(@File_Header,true)
		hierarchical = OBO_Handler.new(@File_Hierarchical,true)
		circular = OBO_Handler.new(@File_Circular,true)
		atomic = OBO_Handler.new(@File_Atomic,true)
		sparse = OBO_Handler.new(@File_Sparse,true)

		assert_equal(false,empty.expand_parentals) # Empty
		assert_equal(false,header.expand_parentals) # Only header
		assert_equal(true,hierarchical.expand_parentals) # Hierarchical
		assert_equal(true,circular.expand_parentals) # Circular
		assert_equal(true,atomic.expand_parentals) # Atomic
		assert_equal(true,sparse.expand_parentals) # Sparse
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
