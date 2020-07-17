# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description class to test OBO_Parser features


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
class TestOBOParserFunctionalities < Minitest::Test
	def setup
		## OBO INFO
		@load_Hierarchical_WithoutIndex = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Hierarchical = [{:file=>File.join(AUX_FOLDER, "hierarchical_sample.obo"), :name=>"hierarchical_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:Parental=>{:id=>:Parental, :name=>"All", :comment=>"none"}, :Child1=>{:id=>:Child1, :name=>"Child1", :is_obsolete => "true", :is_a=>[:Parental], :replaced_by => [:Child2]}, :Child2=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3,:Child4], :is_a=>[:Parental]}, :Child3=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}, :Child4=>{:id=>:Child2, :name=>"Child2", :alt_id=>[:Child3, :Child4], :is_a=>[:Parental]}}, :typedefs=>{}, :instances=>{}}]
		@load_Circular = [{:file=>File.join(AUX_FOLDER, "circular_sample.obo"), :name=>"circular_sample"}, {:"format-version"=>"1.2", :"data-version"=>"test/a/b/c/"}, {:terms=>{:A=>{:id=>:A, :name=>"All", :is_a=>[:C]}, :B=>{:id=>:B, :name=>"B", :is_a=>[:A]}, :C=>{:id=>:C, :name=>"C", :is_a=>[:B]}}, :typedefs=>{}, :instances=>{}}]

		@hierarchical_terms = {Child2: {is_a: [:B]}, Parental: {is_a: [:A]}}
	end

	def test_expand
		# Test regular
		assert_equal([:hierarchical,[:Parental]],OBO_Handler.get_related_ids(:Child2, @load_Hierarchical[2][:terms], :is_a))
		# Test with already expanded info
		aux_expansion = {Parental: [:A]}
		assert_equal([:hierarchical,[:Parental, :A]],OBO_Handler.get_related_ids(:Child2, @load_Hierarchical[2][:terms], :is_a, aux_expansion))		
		# Test with alternatives
		aux_expansion = {Parental: [:A]}
		assert_equal([:hierarchical,[:Parental, :A]],OBO_Handler.get_related_ids(:Child2, @hierarchical_terms, :is_a, aux_expansion, {B: [:Parental]}))		
		# Test circular
		assert_equal([:circular,[:C,:B]],OBO_Handler.get_related_ids(:A, @load_Circular[2][:terms], :is_a))
		assert_equal([:circular,[:B,:A]],OBO_Handler.get_related_ids(:C, @load_Circular[2][:terms], :is_a))
	end

end