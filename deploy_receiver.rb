require 'sinatra'
require 'oj'
require 'shellwords'

set :server, 'puma'

get '/' do
  json = {ok: true}
  Oj.dump(json)
end

post '/deploy' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body, request.env['HTTP_X_SIGNATURE'])

  push = Oj.load(params['payload'])
  puts "Payload: #{push.inspect}"

  send_consul_deploy(
    payload: "#{push['sender']} #{push['source']}",
    application: push['application'],
    environment: push['environment'],
  )

  json = {ok: true}
  Oj.dump(json)
end

post '/kubernetes' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body, request.env['HTTP_X_SIGNATURE'])

  push = Oj.load(params['payload'])
  puts "Payload: #{push.inspect}"

  send_consul_deploy(
    application: 'kubernetes',
    environment: push['environment'],
    payload: "#{push['sender']} #{push['image']} #{push['application']}"
  )

  json = {ok: true}
  Oj.dump(json)
end

post '/github' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body, request.env['HTTP_X_HUB_SIGNATURE'])

  push = Oj.load(params['payload'])
  puts "Payload: #{push.inspect}"

  send_consul_deploy(
    payload: "#{push['sender']['login']} GitHub",
    application: push['repository']['name'],
    environment: push['ref'].split('/').last
  )

  json = {ok: true}
  Oj.dump(json)
end

post '/bitbucket' do
  push = Oj.load(request.body.read)
  puts "Payload: #{push.inspect}"

  push['push']['changes'].each do |change|
    send_consul_deploy(
      payload: "#{push['actor']['username']} BitBucket",
      application: push['repository']['name'].split(/[^A-Za-z]/).first.downcase,
      environment: change['new']['name']
    )
  end
end

def verify_signature(payload_body, signature)
  calc = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(calc, signature)
end

def send_consul_deploy(application:, environment:, payload:)
  application, environment, payload = [Shellwords.escape(application), Shellwords.escape(environment), Shellwords.escape(payload)]

  deploy = "#{application}-#{environment}-deploy"
  puts %Q(Processing deploy command: #{deploy} #{payload})

  consul = `which consul`.chomp
  # Try deploying first with a datacenter, then without
  raise "Could not send deploy command!" unless
    system(%Q(#{consul} event -datacenter="#{environment}" -name="#{deploy}" "#{payload}")) ||
    system(%Q(#{consul} event -name="#{deploy}" "#{payload}"))

  puts "Deploy event fired!"
end
