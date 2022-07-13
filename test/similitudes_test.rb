#! /usr/bin/env ruby

# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description class to test Similitude features


#########################################################
# Load necessary packages
#########################################################

ROOT_FOLDER = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_FOLDER, '../lib'))

# require 'test/unit'
require 'minitest/autorun'
require 'sim_handler'


#########################################################
# Define TESTS
#########################################################
# class TestSimilitudes < Test::Unit::TestCase
class TestSimilitudes < Minitest::Test
	#################################
	# STRING SIMILITUDE
	#################################

	## Check simple similitude
	def test_simple_sim
		assert_equal(-1.0, text_similitude("","")) # Empty both
		assert_equal(-1.0, text_similitude("","abc")) # Empty just one
		assert_equal(-1.0, text_similitude(nil,"abc")) # Nil
		assert_equal(-1.0, text_similitude(8,"abc")) # Not a string
		assert_equal(1, text_similitude("abcde","abcde")) # Exact similitude
		assert_equal(0.75, text_similitude("abcdf","abcde")) # Same length, one char diff
		assert_equal(1, text_similitude("!a%b#d","!a%b#d")) # Special characters at the end
		assert_equal(1, text_similitude("abc\n","abc\t")) # Special characters at the end
		assert_equal(1, text_similitude("\nabc","\tabc")) # Special characters at the beginning
		assert_equal(0.8, text_similitude("abcd","abc")) # Different length
		assert_equal(0, text_similitude("abcd","def")) # Absolute different
		assert_equal(0.6, text_similitude("abcd","asdabcde")) # Subset
		assert_equal(0.5, text_similitude("abcd","abcefd")) # Interference
	end

	## Check sets similitude
	def test_sets_sim
		assert_equal([-1.0],ctext_AtoB([],["abc","def"])) # Empty 
		assert_equal([-1.0],ctext_AtoB(nil,["abc","def"])) # Nil
		assert_equal([-1.0],ctext_AtoB("a",["abc","def"])) # Not array
		assert_equal([1.0,1.0],ctext_AtoB(["abc","def"],["abc","def"])) # Equal sets, same order
		assert_equal([1.0,1.0],ctext_AtoB(["abc","def"],["def","abc"])) # Equal sets, different order
		assert_equal([1.0],ctext_AtoB(["abc"],["abc","def"])) # Subset A
		assert_equal([1.0,0.0],ctext_AtoB(["abc","def"],["abc"])) # Subset B
		assert_equal([0.0,0.0],ctext_AtoB(["abc","def"],["cfg"])) # Absolute different
	end

	## Check complex texts similitude
	def test_complex_sim
		assert_equal(-1.0, complex_text_similitude("","abc|def","|","")) # Empty
		assert_equal(-1.0, complex_text_similitude(nil,"abc|def","|","")) # Nil
		assert_equal(-1.0, complex_text_similitude([],"abc|def","|","")) # Not string
		assert_equal(1, complex_text_similitude("abc|def","abc|def","|","")) # Complex equal, non config
		assert_equal(1, complex_text_similitude("abc|def","abc|de%f","|","%")) # Complex equal, removing chars
		assert_equal(0.5, complex_text_similitude("abc|def","abc|ajk","|","")) # Complex partially equal
		assert_equal(0.5, complex_text_similitude("abc|ajk","abc|def","|","")) # Complex partially equal (2)
		assert_equal(0.75, complex_text_similitude("abc","abc|def","|","")) # Complex against not complex
		assert_equal(0.0, complex_text_similitude("abc|def","ghk|jlmn","|","")) # Complex all different
	end

	## Check complex set similitudes
	def test_complex_set_sim
		assert_nil(nil,similitude_network([], splitChar: ";", charsToRemove: "", unique: false)) # Empty
		assert_nil(nil,similitude_network(nil, splitChar: ";", charsToRemove: "", unique: false)) # Nil
		assert_nil(nil,similitude_network("", splitChar: ";", charsToRemove: "", unique: false)) # Not array
		assert_equal({},similitude_network(["a"], splitChar: ";", charsToRemove: "", unique: false)) # Single element
		assert_equal({"abc"=>{"def"=>0.0}},similitude_network(["abc","def"], splitChar: ";", charsToRemove: "", unique: false)) # Simple without repetition
		assert_equal({"abc"=>{"def"=>0.0}},similitude_network(["abc","def","abc"], splitChar: ";", charsToRemove: "", unique: true)) # Simple with repetitions - filtered
		assert_equal({"abcdf"=>{"abcde"=>0.75}},similitude_network(["abcdf","abcde","abcdf"], splitChar: ";", charsToRemove: "", unique: true)) # Simple with repetitions (2) - filtered
		assert_equal({"abcdf"=>{"abcdf"=>1.0}},similitude_network(["abcdf","abcdf"], splitChar: ";", charsToRemove: "", unique: false)) # Simple with repetitions - unfiltered
	end


	#################################
	# ROBINSON-RESNICK SIMILITUDE
	#################################

	#################################
	# NLP SIMILITUDES
	#################################

end