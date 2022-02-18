#! /usr/bin/env ruby

# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description script to calculate similitude between disease names



#########################################################
# AUTHOR NOTES
#########################################################

# 1 - 

#########################################################
# Load necessary packages
#########################################################
ROOT_FOLDER = File.dirname(__FILE__)
$: << File.expand_path(File.join(ROOT_FOLDER, '..', 'lib'))
$: << File.expand_path(File.join(ROOT_FOLDER, '..', 'lib', 'semtools'))

require 'optparse'
require 'text'
require 'sim_handler'


#########################################################
# Configure OPT parser
#########################################################
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  options[:input_file] = nil
  opts.on("-i", "--input_file PATH", "Input OMIM diseases file") do |input_file|
    options[:input_file] = input_file
  end

  options[:split_char] = "\t"
  opts.on("-s", "--split_char STRING", "Character for splitting input file. Default: tab") do |split_char|
    options[:split_char] = split_char
  end

  options[:cindex] = 0
  opts.on( '-c', '--column INTEGER', 'Column index wich contains texts to be compared. Default: 0' ) do |opt|
      options[:cindex] = opt.to_i
  end

  options[:findex] = -1
  opts.on( '-C', '--filter_column INTEGER', '[OPTIONAL] Column index wich contains to be used as filters. Default: -1' ) do |opt|
      options[:findex] = opt.to_i
  end

  options[:filter_value] = nil
  opts.on("-f", "--filter_value STRING", "[OPTIONAL] Value to be used as filter") do |opt|
    options[:filter_value] = opt
  end

  options[:rm_char] = ""
  opts.on("-r", "--remove_chars STRING", "Chars to be excluded from comparissons") do |chars2remove|
    options[:rm_char] = chars2remove
  end

  options[:output_file] = nil
  opts.on("-o", "--output_file PATH", "Output similitudes file") do |output_file|
    options[:output_file] = output_file
  end


end.parse!


#########################################################
# Define useful functions
#########################################################

def load_table_file(input_file, splitChar = "\t",targetCol = 1, filterCol = -1, filterValue = nil)
	texts = Array.new
	# Read
	File.open(input_file).each do |line|
    line.chomp!
		row = line.split(splitChar)
    if filterCol >= 0
      next unless row[filterCol] == filterValue
    end
    texts.push row[targetCol]	
	end
	# Remove uniques
	texts.uniq!
	# Return
	return texts
end


#########################################################
# MAIN
#########################################################
# puts options[:input_file]
# puts options[:split_char]
# puts options[:cindex]
# puts options[:findex]
# puts options[:filter_value]
# puts options[:output_file]
# puts options[:rm_char]

# Verbose point
puts "Loading input data"

# Load info
texts2compare = load_table_file(input_file = options[:input_file],
                                 splitChar = options[:split_char],
                                 targetCol = options[:cindex],
                                 filterCol = options[:findex],
                                 filterValue = options[:filter_value])
# Verbose point
puts "Calculating similitude for (" + texts2compare.length.to_s + ") elements"

# Obtain all Vs all
similitudes_AllVsAll = similitude_network(texts2compare, charsToRemove: options[:rm_char])

# Verbose point
puts "Writing output file ..."

# Iter and store
File.open(options[:output_file],"w") do |f|
  similitudes_AllVsAll.each do |item,item_similitudes|
    item_similitudes.each do |item2, sim|
      info = [item,item2,sim]
      f << info.join("\t").concat("\n")
    end
  end
end

# Verbose point
puts "End of similitude process"
