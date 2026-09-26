# config.ru

require 'rack/app'
require 'json'
require './app/app.rb'

class App < Rack::App
  desc 'Liveness probe etc'
  get '/' do
    'Hello!'
  end

  desc 'Payments endpoint '
  post '/bulk_pay' do
    req = Rack::Request.new(env)
    if req.post?
      raw_body = req.body.read
      payload = JSON.parse(raw_body)
      processing_result = ProcessPayments.call(payload)
      [200, {"Content-Type" => "application/json"}, [{message: "received"}]]
    else
      [405, {"Content-Type" => "text/plain"}, ["Method Not Allowed"]]
    end
  end
end

run App
