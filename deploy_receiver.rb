require 'sinatra'
require 'oj'
require 'shellwords'
require 'diplomat'

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
    sender: push['sender'],
    source: push['source'],
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
    sender: push['sender'],
    source: push['source'],
    payload: "#{push['sender']} #{push['image']} #{push['application']}",
    stack: push['stack']
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

  environments = [push['ref'].split('/').last]
  # If master is getting deployed, try pushing everywhere and hope something is listening
  if environments == ['master']
    environments = ['staging', 'production']
  end

  environments.each do |environment|
    send_consul_deploy(
      payload: "#{push['sender']['login']} GitHub",
      sender: push['sender']['login'],
      source: 'GitHub',
      application: push['repository']['name'],
      environment: environment
    )
  end

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

def send_consul_deploy(application:, environment:, payload:, stack: nil)
  stack = environment unless stack

  application, environment = [Shellwords.escape(application), Shellwords.escape(environment)]

  deploy = "#{application}-#{stack}-deploy"
  puts %Q(Processing deploy command: #{deploy} #{payload})

  dc = Diplomat::Datacenter.get.include?(environment) ? environment : nil
  Diplomat::Event.fire(deploy, payload, nil, nil, nil, dc)

  puts "Deploy event fired!"
end
