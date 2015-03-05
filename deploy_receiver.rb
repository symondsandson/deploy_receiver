require 'sinatra'
require 'oj'
require 'shellwords'

set :server, 'puma'

get '/' do
  json = {ok: true}
  Oj.dump(json)
end

post '/github' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)
  push = Oj.load(params['payload'])

  puts "Payload: #{push.inspect}"

  sender = push['sender']['login']
  application = push['repository']['name']
  environment = push['ref'].split('/').last
  send_consul_deploy(application, environment, sender, 'GitHub')

  json = {ok: true}
  Oj.dump(json)
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end

def send_consul_deploy(application, environment, sender, source)
  application, environment, sender, source = [Shellwords.escape(application), Shellwords.escape(environment), Shellwords.escape(sender), Shellwords.escape(source)]

  deploy = "#{application}-#{environment}-deploy"
  payload = "#{sender} #{source}"
  puts %Q(Processing deploy command: #{deploy} #{payload})

  `/usr/local/bin/consul event -name="#{deploy}" "#{payload}"`
end
