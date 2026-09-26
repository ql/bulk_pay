require 'rack/app'

class App < Rack::App

  desc 'some hello endpoint'
  get '/hello' do
    'Hello World!'
  end
end
