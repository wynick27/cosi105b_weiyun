

class MovieData
  def load_data
    File.open('ml-100k/u.data', "r") do |f|
      @movies=Hash.new(0)
	  @users=Hash.new { |hash, key| hash[key] = [] }
	  f.each_line do |line|
        item=line.split.map {|x| x.to_i}
		@movies[item[1]] += 1
		@users[item[0]].push item[1]
      end
	  @popularity_list=@movies.to_a.sort_by! { |x| -x[1] }.map { |x| x[0]}
    end
  end
  
  def popularity(movie_id)
    @movies[movie_id]
  end
  
  def popularity_list
    @popularity_list
  end
  
  def similarity(user1,user2)
    (@users[user1] & @users[user2]).length
  end
  
  def most_similar(u) 
    @users.keys.map {|u2| [u2,similarity(u,u2)]}.sort_by! { |x| -x[1]}.map { |x| x[0]}[1,10]
  end
 end
  