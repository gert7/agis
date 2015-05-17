Gem::Specification.new do |s|
  s.name        = 'agis'
  s.version     = '0.1.1'
  s.date        = '2015-05-17'
  s.summary     = "Messagebox Redis Actors for Ruby"
  s.description = "Messagebox Redis Actors for Ruby and ActiveRecord"
  s.authors     = ["Gert Oja"]
  s.email       = 'gertoja1@gmail.com'
  s.files       = ["lib/agis.rb"]
  s.homepage    =
    'http://rubygems.org/gems/agis'
  s.license       = 'MIT'
  s.add_development_dependency "redis"
  s.add_development_dependency "mlanett-redis-lock"
end
