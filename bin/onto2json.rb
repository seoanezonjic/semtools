#! /usr/bin/env ruby

# 
# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>

ROOT_PATH = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_PATH, '..', 'lib', 'semtools'))

require 'optparse'
require 'semtools'

##########################
# OPT-PARSER
##########################

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  options[:input_file] = nil
  opts.on("-i", "--input_file PATH", "Input file with ontology in OBO format") do |data|
    options[:input_file] = data
  end

  options[:output_file] = nil
  opts.on("-o", "--output_file PATH", "Output path") do |data|
    options[:output_file] = data
  end
  
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end

end.parse!


##########################
# MAIN
##########################
puts "Loading ontology ..."
onto = Ontology.new(file: options[:input_file], load_file: true)
puts "Exporting ontology to JSON ..."
onto.write(options[:output_file])
puts "Ontology exported"