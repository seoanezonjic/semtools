# TODO: Make a pull request to https://rubygems.org/gems/ruby-statistics, with all the statistic code implemented here.
#to cmpute fisher exact test
#Fisher => http://www.biostathandbook.com/fishers.html
def get_fisher_exact_test(listA, listB, all_elements_count, tail ='two_sided', weigths=nil)
	listA_listB = listA & listB
	listA_nolistB = listA - listB
	nolistA_listB = listB - listA
	if weigths.nil?
		listA_listB_count = listA_listB.length
		listA_nolistB_count = listA_nolistB.length
		nolistA_listB_count = nolistA_listB.length
		nolistA_nolistB_count = all_elements_count - (listA | listB).length
	else
		# Fisher exact test weigthed as proposed in Improved scoring of functional groups from gene expression data by decorrelating GO graph structure
		# https://academic.oup.com/bioinformatics/article/22/13/1600/193669
		listA_listB_count = listA_listB.map{|i| weigths[i]}.inject(0){|sum, n| sum + n}.ceil
		listA_nolistB_count = listA_nolistB.map{|i| weigths[i]}.inject(0){|sum, n| sum + n}.ceil
		nolistA_listB_count = nolistA_listB.map{|i| weigths[i]}.inject(0){|sum, n| sum + n}.ceil
		nolistA_nolistB_count = (weigths.keys - (listA | listB)).map{|i| weigths[i]}.inject(0){|sum, n| sum + n}.ceil
		all_elements_count = weigths.values.inject(0){|sum, n| sum + n}.ceil
	end
	if tail == 'two_sided'
		accumulated_prob = get_two_tail(listA_listB_count, listA_nolistB_count, nolistA_listB_count, nolistA_nolistB_count, all_elements_count)
	elsif tail == 'less' 
		accumulated_prob = get_less_tail(listA_listB_count, listA_nolistB_count, nolistA_listB_count, nolistA_nolistB_count, all_elements_count)
	end
	return accumulated_prob
end

def get_two_tail(listA_listB_count, listA_nolistB_count, nolistA_listB_count, nolistA_nolistB_count, all_elements_count)
	#https://www.sheffield.ac.uk/polopoly_fs/1.43998!/file/tutorial-9-fishers.pdf
	accumulated_prob = 0
	ref_prob = compute_hyper_prob(
		listA_listB_count, 
		listA_nolistB_count, 
		nolistA_listB_count, 
		nolistA_nolistB_count, 
		all_elements_count
	)
	accumulated_prob += ref_prob
	[listA_listB_count, nolistA_nolistB_count].min.times do |n| #less
		n += 1
		prob = compute_hyper_prob(
			listA_listB_count - n, 
			listA_nolistB_count + n, 
			nolistA_listB_count + n, 
			nolistA_nolistB_count - n, 
			all_elements_count
		)
		prob <= ref_prob ? accumulated_prob += prob : break
	end

	[listA_nolistB_count, nolistA_listB_count].min.times do |n| #greater
		n += 1
		prob = compute_hyper_prob(
			listA_listB_count + n, 
			listA_nolistB_count - n, 
			nolistA_listB_count - n, 
			nolistA_nolistB_count + n, 
			all_elements_count
		)
		accumulated_prob += prob if prob <= ref_prob
	end

	return accumulated_prob
end

def get_less_tail(listA_listB_count, listA_nolistB_count, nolistA_listB_count, nolistA_nolistB_count, all_elements_count)
	accumulated_prob = 0
	[listA_listB_count, nolistA_nolistB_count].min.times do |n|
		accumulated_prob += compute_hyper_prob(
			listA_listB_count - n, 
			listA_nolistB_count + n, 
			nolistA_listB_count + n, 
			nolistA_nolistB_count - n, 
			all_elements_count
		)
	end
	return accumulated_prob
end

def compute_hyper_prob(a, b, c, d, n)
	# https://en.wikipedia.org/wiki/Fisher%27s_exact_test
	binomA = binom(a + b, a)
	binomC = binom(c + d, c)
	divisor = binom(n, a + c)
	return (binomA * binomC).fdiv(divisor)
end

def binom(n,k)
	if k > 0 && k < n
		res = (1+n-k..n).inject(:*)/(1..k).inject(:*)
	else
		res = 1
	end
end

#to cmpute adjusted pvalues
#https://rosettacode.org/wiki/P-value_correction#Ruby
def get_benjaminiHochberg_pvalues(arr_pvalues)
	n = arr_pvalues.length
	arr_o = order(arr_pvalues, true)
	arr_cummin_input = []
	(0..(n - 1)).each do |i|
		arr_cummin_input[i] = (n / (n - i).to_f) * arr_pvalues[arr_o[i]]
	end
	arr_ro = order(arr_o)
	arr_cummin = cummin(arr_cummin_input)
	arr_pmin = pmin(arr_cummin)
	return arr_pmin.values_at(*arr_ro)
end

def order(array, decreasing = false)
	if decreasing == false
		array.sort.map { |n| array.index(n) }
	else
		array.sort.map { |n| array.index(n) }.reverse
	end
end

def cummin(array)
	cumulative_min = array.first
	arr_cummin = []
	array.each do |p|
		cumulative_min = [p, cumulative_min].min
		arr_cummin << cumulative_min
	end
	return arr_cummin
end

def pmin(array)
	x = 1
	pmin_array = []
	array.each_index do |i|
		pmin_array[i] = [array[i], x].min
		abort if pmin_array[i] > 1
	end
	return pmin_array
end

