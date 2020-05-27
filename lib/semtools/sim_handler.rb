# @author Fernando Moreno Jabato <jabato(at)uma(dot)es>
# @description functionalities to handle similitude features



# Applies the WhiteSimilarity from 'text' package over two given texts
# Param:
# +textA+:: text to be compared with textB
# +textB+:: text to be compared with textA
# Returns the similarity percentage between [0,1]
def text_similitude(textA, textB)
  # Check special cases
  return -1.0 if (textA.nil?) | (textB.nil?)
  return -1.0 if (!textA.is_a? String) | (!textB.is_a? String)
  return -1.0 if (textA.length <= 0) | (textB.length <= 0)
  # Calculate similitude
  require 'text'
  white = Text::WhiteSimilarity.new
  return white.similarity(textA.lstrip, textB.lstrip)
end  

# Applies the WhiteSimilarity from 'text' package over two given text sets and returns the similitudes
# of the each element of the first set over the second set 
# Param:
# +textsA+:: text set to be compared with textsB
# +textsB+:: text set to be compared with textsA
# Returns the maximum similarity percentage between [0,1] for each element of textsA against all elements of textsB
def ctext_AtoB(textsA, textsB)
  # Check special cases
  return [-1.0] if (textsA.nil?) | (textsB.nil?)
  return [-1.0] if (!textsA.is_a? Array) | (!textsB.is_a? Array)
  return [-1.0] if (textsA.length <= 0) | (textsB.length <= 0)
  # Calculate similitude
  similitudesA = []
  textsA.each do |fragA|
    frag_A_similitudes = []
    textsB.each do |fragB|
      frag_A_similitudes << text_similitude(fragA, fragB)
    end
    begin 
      similitudesA << frag_A_similitudes.max
    rescue => e
      STDERR.puts frag_A_similitudes.inspect
      STDERR.puts textsA.inspect , textsB.inspect
      STDERR.puts e.message
      STDERR.puts e.backtrace
      Process.exit
    end 
  end
  return similitudesA
end

# Applies the WhiteSimilarity from 'text' package over two given complex texts.
# Complex texts will be splitted and compared one by one from A to B and B to A
# Param:
# +textA+:: text to be compared with textB
# +textB+:: text to be compared with textA
# +splitChar+:: char to split text* complex names
# +charsToRemove+:: char (or chars set) to be removed from text to be compared
# Returns the similarity percentage between [0,1] obtained by bidirectional all Vs all similarity
def complex_text_similitude(textA, textB, splitChar = ";", charsToRemove = "")
  # Check special cases
  return -1.0 if (textA.nil?) | (textB.nil?)
  return -1.0 if (!textA.is_a? String) | (!textB.is_a? String)
  return -1.0 if (textA.length <= 0) | (textB.length <= 0)
  # Split&Clean both sets
  textA_splitted = textA.split(splitChar)
  textA_splitted.map! {|str| str.gsub(/["#{charsToRemove}"]/,'')}
  textA_splitted.select! {|str| str.length > 0}
  textB_splitted = textB.split(splitChar)
  textB_splitted.map! {|str| str.gsub(/["#{charsToRemove}"]/,'')}
  textB_splitted.select! {|str| str.length > 0}
  # Per each X elemnt, compare against all Y elements
  similitudesA = ctext_AtoB(textA_splitted, textB_splitted)
  similitudesB = ctext_AtoB(textB_splitted, textA_splitted)
  # Obtain bidirectional similitude
  similitudesA = similitudesA.inject{ |sum, el| sum + el }.to_f / similitudesA.size
  similitudesB = similitudesB.inject{ |sum, el| sum + el }.to_f / similitudesB.size
  # Obtain bidirectional similitude
  bidirectional_sim = (similitudesA + similitudesB) / 2
  # Return info
  return bidirectional_sim
end

# Applies the WhiteSimilarity from 'text' package over all complex text stored into an array.
# Complex texts will be splitted and compared one by one from A to B and B to A
# Param:
# +items_array+:: text elements to be compared all against others
# +splitChar+:: char to split text* complex names
# +charsToRemove+:: char (or chars set) to be removed from texts to be compared
# +unique+:: boolean flag which indicates if repeated elements must be removed
# Returns the similarity percentage for all elements into array
def similitude_network(items_array, splitChar = ";", charsToRemove = "", unique = false)
  # Special cases
  return nil if items_array.nil?
  return nil if !items_array.is_a? Array
  return nil if items_array.length <= 0
  # Remove repeated elements
  items_array.uniq! if unique
  # Define hash to be filled
  sims = {}
  # Per each item into array => Calculate similitude
  while(items_array.length > 1)
    current = items_array.shift
    sims[current] = {}
    items_array.each do |item|
      sims[current][item] = complex_text_similitude(current,item,splitChar,charsToRemove)
    end
  end 
  return sims
end