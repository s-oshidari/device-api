require 'sinatra'
require 'sinatra/reloader'

configure do
  disable :show_exceptions
end

load 'api/status-led.rb'
#load 'test/mongo.rb'
#load 'test/helper.rb'
#load 'test/env.rb'

get '/' do
  erb :index
end

=begin
get '/*' do
  redirect '/'
end
=end

