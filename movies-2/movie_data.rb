module Enumerable
  def sum
    inject(0.0) { |result, el| result + el }
  end

  def mean 
    sum / size
  end
  
  def geo_mean
    Math.sqrt(self.square_sum)
  end
  
  def square_sum
    self.inject(0.0){|accum, i| accum +i**2 }
  end
  
  def var
    m = self.mean
    sum = self.inject(0.0){|accum, i| accum +(i-m)**2 }
    sum/self.length
  end
  
  def rms
    Math.sqrt(self.square_sum/self.length)
  end

  def stdev
    return Math.sqrt(self.var)
  end
  
  def col(cname)
    map {|x| x[cname]}
  end
end

class MovieData
  
  attr_reader :trainset,:testset
  
  #reads the dataset
  def load_data(folder,dataset=nil)
    train = dataset == nil ? "#{folder}/u.data" : "#{folder}/#{dataset.to_s}.base" 
    test = dataset == nil ? "" : "#{folder}/#{dataset.to_s}.test"
    @trainset=read_file train
    @testset=read_file test
    #build user and movie index using hashes
    @user_index=@trainset.group_by { |item| item.u_id }
    @movie_index=@trainset.group_by { |item| item.m_id }
    @rating_index={}
    @trainset.each {|item| @rating_index[[item.u_id,item.m_id]]=item.rating }
  end
  
  #reads a specific dataset and returns a array of a structure with u_id,m_id,rating and time 
  def read_file(path)
    struct=Struct.new(:u_id, :m_id,:rating,:time)
    puts path
    return [] if !File.exists? path
    File.open(path, "r") do |f|
    #splits each line by ws and convert to integer and build structures from values
      return f.each_line.map { |line| struct.new(*line.split.map {|x| x.to_i}) }
    end
  end
  
  
  def popularity(movie_id)
    @movie_index[movie_id].size
  end
  
  def popularity_list
  #build list by sorting by the number of reviews and caches it
    @popularity_list=@movie_index.sort_by { |x| -x[1].size }.col(0) if @popularity_list.nil?
    @popularity_list
  end
    
  def rating(user_id,movie_id)
    @rating_index[[user_id,movie_id]]
    #item=@user_index[user_id].index { |item| item.m_id == movie_id }
    #item.nil? ? 0.0 : item.rating
  end
  
  def avg_rating(user_id)
    @user_index[user_id].col(:rating).mean
  end
  
  #returns movies rated by user or all movies if u_id is nil
  def movies(u_id=nil)
    if u_id.nil? then
      @movie_index.keys
    else
      @user_index[u_id].col(:m_id)
    end
  end
  
  #returns users that reviewed the movie or all users if m_id is nil
  def viewers(m_id=nil)
    if m_id.nil? then
      @user_index.keys
    else
      @movie_index[m_id].col(:u_id)
    end
  end

end

#module of similarity measures
module Similarity
  #returns the common movie count as a measure
  def self.common(data,u1,u2)
    (data.movies(u1) & data.movies(u2)).size
  end
  #using cosine similarity
  def self.cosine(data,u1,u2)
    m1=data.movies(u1)
    m2=data.movies(u2)
    mc=m1 & m2
    r1=m1.map {|m_id| data.rating(u1,m_id) }
    r2=m2.map {|m_id| data.rating(u2,m_id) }
    rc=mc.map {|m_id| data.rating(u1,m_id) * data.rating(u2,m_id) }
    var=rc.sum / (r1.geo_mean * r2.geo_mean)
    var.finite? ? var : 0.0
  end
  #using person measure
  def self.pearson(data,u1,u2)
    mc=data.movies(u1) & data.movies(u2)
    return 0.0 if mc.empty?
    r1_avg = data.avg_rating(u1)
    r2_avg = data.avg_rating(u2)
    cov = mc.map {|m_id| (data.rating(u1,m_id) - r1_avg) * (data.rating(u2,m_id) - r2_avg)}.sum
    stdev1 = mc.map {|m_id| (data.rating(u1,m_id) - r1_avg)}.geo_mean
    stdev2 = mc.map {|m_id| (data.rating(u2,m_id) - r2_avg)}.geo_mean
    var=cov / (stdev1 * stdev2)
    var.finite? ? var : 0.0
  end
end

#module of aggregation methods, takes a list of (rating,similarity) of similar users

module Aggregation
  #predict by all similar user's average ratings
  def self.average(data,u_id,ratings)
    ratings.col(0).mean
  end
  #predict by all similar user's average ratings weighted by similarity
  def self.weight_average(data,u_id,ratings)
    ratings.map {|item| item[0]*item[1]}.sum / ratings.col(1).map{|x| x.abs}.sum
  end
  def self.mean_average(data,u_id,ratings)
    mean=data.avg_rating(u_id)
    mean + ratings.map {|item| (item[0]-mean)*item[1]}.sum / ratings.col(1).map{|x| x.abs}.sum
  end
end


class Predicter
  attr_reader :data
  
  def initialize(data,similarity,aggragation)
    @data=data
    @similarity_func=similarity
    @aggragation_func=aggragation
  end
  
  
  def similarity(user1,user2)
    @similarity_func.call(data,user1,user2)
  end
  
  #return a list of tuples with (userid,similarity)
  def most_similar(u_id,m_id=nil,count=25) 
    #get all users watched movie m_id
    users=data.viewers(m_id) - [u_id]
    result=users.map {|u2| [u2,similarity(u_id,u2)]}.sort_by! { |x| -x[1]}
    count.nil? ? result : result.take(count)
  end
 
  #predict one movie rating
  def predict(u_id,m_id)
    sim=most_similar(u_id,m_id).map { |item| [data.rating(item[0],m_id),item[1]] }
    @aggragation_func.call(data,u_id,sim)
  end
    
  #predict the top k items in the test set
  def run_test(k)
    MovieTest.new(@data.testset.take(k).map {|item| [item.u_id,item.m_id,item.rating,predict(item.u_id,item.m_id)]})
  end
  
end

class MovieTest
  attr_reader :mean,:stdev,:rms
  
  def initialize(data)
    @data=data
    error=@data.map {|item| (item[2]-item[3]).abs}
    @mean=error.mean
    @stdev=error.stdev
    @rms=error.rms
  end
  
  def to_a
    @data
  end
end

data = MovieData.new
data.load_data('ml-100k',:u1) 
p = Predicter.new(data,Similarity.method("pearson"),Aggregation.method("mean_average"))
puts p.run_test(50).inspect