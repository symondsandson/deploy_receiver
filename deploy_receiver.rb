require 'sinatra'
require 'oj'
require 'shellwords'
require 'net/http'

set :server, 'puma'

get '/' do
  json = {ok: true}
  Oj.dump(json)
end

post '/deploy' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)
  push = Oj.load(params['payload'])

  puts "Payload: #{push.inspect}"

  sender = push['sender']['login']
  set_consul_user(sender)

  application = push['repository']['name']
  environment = push['ref'].split('/').last
  send_consul_deploy(application, environment)

  json = {ok: true}
  Oj.dump(json)
end

def consul_server
  Net::HTTP.new('localhost', 8500)
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end

def set_consul_user(sender)
  sender = Shellwords.escape(sender)
  puts "Sender: #{sender}"
  consul_server.send_request('PUT', "/v1/kv/deploy/sender", sender)
end

def send_consul_deploy(application, environment)
  application, environment = [Shellwords.escape(application), Shellwords.escape(environment)]
  puts "Processing deploy event: #{deploy}"
  deploy = "#{application}-#{environment}-deploy"
  consul_server.send_request('PUT', "/v1/event/fire/#{deploy}", sender)
end
