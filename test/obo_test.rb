#! /usr/bin/env ruby

# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description class to test OBO_Handler features


#########################################################
# Load necessary packages
#########################################################

BASE_FOLDER = File.dirname(File.expand_path(__FILE__))
$: << File.expand_path(File.join(BASE_FOLDER, '..', 'lib', 'semtools'))
#$: << File.expand_path(File.join(BASE_FOLDER, '../lib'))
AUX_FOLDER = File.join(BASE_FOLDER, 'aux_files')

# require 'test/unit'
require 'minitest/autorun'
require 'obo_handler'

#########################################################
# Define TESTS
#########################################################
# class TestSimilitudes < Test::Unit::TestCase
class TestOBOFunctionalities < Minitest::Test

	def setup
		# Files
		@file_Header = {file: File.join(AUX_FOLDER, "only_header_sample.obo"), name: "only_header_sample"}
		@file_Hierarchical = {file: File.join(AUX_FOLDER, "hierarchical_sample.obo"), name: "hierarchical_sample"}
		@file_Circular = {file: File.join(AUX_FOLDER, "circular_sample.obo"), name: "circular_sample"}
		@file_Atomic = {file: File.join(AUX_FOLDER, "sparse_sample.obo"), name: "sparse_sample"}
		@file_Sparse = {file: File.join(AUX_FOLDER, "sparse2_sample.obo"), name: "sparse2_sample"}

		## OBO INFO
		@load_Header = [{:file=>File.join(AUX_FOLDER, "only_header_sample.obo"), :name=>"only_header_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical_WithoutIndex = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}, :Child3=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, :Child4=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Circular = [{:file=>File.join(AUX_FOLDER, "circular_sample.obo"), :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All", :is_a=>[:C]}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:B]}}, :typedefs=>{}, :instances=>{}}]
		@load_Atomic = [{:file=>File.join(AUX_FOLDER, "sparse_sample.obo"), :name=>"sparse_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1"}, :Child2=>{:id=>:Child2, :name=>"Child2"}}, :typedefs=>{}, :instances=>{}}]
		@load_Sparse = [{:file=>File.join(AUX_FOLDER, "sparse2_sample.obo"), :name=>"sparse2_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All"}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:A]}, :D=>{:id=>:D, :name=>"Sparsed"}}, :typedefs=>{}, :instances=>{}}]

		# Parentals
		@parentals_Hierachical = [:hierarchical, {:Child1=>[:Parental], :Child2=>[:Parental], :Child3=>[:Parental], :Child4=>[:Parental]}]
		@parentals_Circular = [:circular, {:A=>[:C, :B], :C=>[:B, :A], :B=>[:A, :C]}]
		@parentals_Atomic = [:atomic, {}]
		@parentals_Sparse = [:sparse, {:B=>[:A], :C=>[:A]}]

		# Aux variables
		@basic_tags = {:ancestors => [:is_a], :obsolete => [:is_obsolete], :alternative => [:alt_id,:replaced_by,:consider]}
		@empty_ICs = {:resnick=>{}, :resnick_observed=>{}, :seco=>{}, :zhou=>{}, :sanchez=>{}}
		@erroneous_freq = {:struct_freq=>-1.0, :observed_freq=>-1.0, :max_depth=>-1.0}
		@empty_file = {:file=>nil, :name=>nil}

		# Create necessary instnaces
		@hierarchical = OBO_Handler.new(file: @file_Hierarchical[:file],load_file: true)
		@circular = OBO_Handler.new(file: @file_Circular[:file],load_file: true)
		@atomic = OBO_Handler.new(file: @file_Atomic[:file],load_file: true)
		@sparse = OBO_Handler.new(file: @file_Sparse[:file],load_file: true)

		# Freqs variables
		@hierarchical_freqs_default = {:struct_freq=>2.0, :observed_freq=>-1.0, :max_depth=>1.0}
		@hierarchical_freqs_updated = {:struct_freq=>2.0, :observed_freq=> 2.0, :max_depth=>1.0}
	end

	#################################
	# INIT AND CLASS FUNCTIONALITIES
	#################################

	def test_load_file
		assert_raises Errno::ENOENT do OBO_Handler.load_obo("./.rb") end # Erroneous file path
		assert_equal(@load_Header,OBO_Handler.load_obo(@file_Header[:file])) # Only header
		assert_equal(@load_Hierarchical_WithoutIndex,OBO_Handler.load_obo(@file_Hierarchical[:file])) # Hierarchical
		assert_equal(@load_Circular,OBO_Handler.load_obo(@file_Circular[:file])) # Circular
		assert_equal(@load_Atomic,OBO_Handler.load_obo(@file_Atomic[:file])) # Sparsed
		assert_equal(@load_Sparse,OBO_Handler.load_obo(@file_Sparse[:file])) # Sparsed 2
	end

	def test_expand
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: nil,target_tag: "")) # Nil terms
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: {},target_tag: "")) # Empty terms
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: [],target_tag: "")) # Terms not a hash
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: nil)) # Nil target
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: "")) # No/Empty target
		# assert_nil(OBO_Handler.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: 8)) # Target not a string
		# assert_raises ArgumentError do OBO_Handler.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: :is_a,split_info_char:" ! ",split_info_indx: -1) end # Erroneous info_indx
		assert_raises TypeError do OBO_Handler.get_related_ids_by_tag(terms: {:A=>[1,2]},target_tag: :is_a) end # Terms without correct format {id, {tags}}
		assert_equal(@parentals_Hierachical,OBO_Handler.get_related_ids_by_tag(terms: @load_Hierarchical[2][:terms],target_tag: :is_a)) # Hierarchical structure
		assert_equal(@parentals_Circular,OBO_Handler.get_related_ids_by_tag(terms: @load_Circular[2][:terms],target_tag: :is_a)) # Circular structure
		assert_equal(@parentals_Atomic,OBO_Handler.get_related_ids_by_tag(terms: @load_Atomic[2][:terms],target_tag: :is_a)) # Sparse structure
		assert_equal(@parentals_Sparse,OBO_Handler.get_related_ids_by_tag(terms: @load_Sparse[2][:terms],target_tag: :is_a)) # Sparse structure with some other structures
	end




	#################################
	# SPECIAL TAGS FUNCTIONALITIES
	#################################

	def test_load
		## Check info
		# Header
		assert_equal(@load_Hierarchical[1],@hierarchical.header)
		assert_equal(@load_Circular[1],@circular.header)
		assert_equal(@load_Atomic[1],@atomic.header)		
		assert_equal(@load_Sparse[1],@sparse.header)		
		# Stanzas
		assert_equal(@load_Hierarchical[2],@hierarchical.stanzas)
		assert_equal(@load_Circular[2],@circular.stanzas)
		assert_equal(@load_Atomic[2],@atomic.stanzas)		
		assert_equal(@load_Sparse[2],@sparse.stanzas)		
	end

	def test_obj_parentals
		# Parentals
		@hierarchical.get_index_parentals # Hierarchical
		@circular.get_index_parentals # Circular
		@atomic.get_index_parentals # Atomic
		@sparse.get_index_parentals # Sparse
	end

	def test_frequencies
		@hierarchical.build_index
		# Check freqs
		assert_equal(@hierarchical_freqs_default,@hierarchical.max_freqs) # Only structural freq
		# Update hierarchical observed freq
		@hierarchical.add_observed_terms(terms: ["Child2","Child2"], transform_to_sym: true)
		# Check observed freq
		assert_equal(@hierarchical_freqs_updated,@hierarchical.max_freqs) # Only structural freq
	end


	def test_ics
		@hierarchical.build_index
		assert_equal(0, @hierarchical.get_IC(term: :Parental))	# Root
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(term: :Child2)) # Leaf	
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(term: :Child1)) # Obsolete
		assert_equal(-Math.log10(1.fdiv(2)), @hierarchical.get_IC(term: :Child3)) # Alternative
	end

	def test_export_import
		# Add extra info to instance
		@hierarchical.build_index
		@hierarchical.get_IC(term: :Child2)
		# Export object to JSON
		@hierarchical.write(File.join(AUX_FOLDER, "testjson.json"))
		#file: File.join(AUX_FOLDER, "testjson.json"
		obo = OBO_Handler.new()
		obo.read(File.join(AUX_FOLDER, "testjson.json"))
		# Import
		assert_equal(@hierarchical, obo)
		# Remove generated files
		File.delete(File.join(AUX_FOLDER, "testjson.json"))
	end

	#################################
	# METADATA FUNCTIONALITIES
	#################################

	def test_dictionaries
		assert_equal({Parental: 'All', Child2: 'Child2'}, @hierarchical.calc_dictionary(:name)[:byTerm])
		assert_equal(:Parental, @hierarchical.translate('All',:name))
		assert_equal('Child2', @hierarchical.translate(:Child2,:name, byValue: false)) # Official term
		assert_equal('Child2', @hierarchical.translate(:Child4,:name, byValue: false)) # Alternative term		
	end

end
