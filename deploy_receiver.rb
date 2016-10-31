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
    sender: push['sender'],
    application: push['application'],
    environment: push['environment'],
    source: push['source']
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
    sender: push['sender']['login'],
    application: push['repository']['name'],
    environment: push['ref'].split('/').last,
    source: 'GitHub'
  )

  json = {ok: true}
  Oj.dump(json)
end

post '/bitbucket' do
  push = Oj.load(request.body.read)
  puts "Payload: #{push.inspect}"

  push['push']['changes'].each do |change|
    send_consul_deploy(
      sender: push['actor']['username'],
      application: push['repository']['name'].split(/[^A-Za-z]/).first.downcase,
      environment: change['new']['name'],
      source: 'BitBucket'
    )
  end
end

def verify_signature(payload_body, signature)
  calc = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(calc, signature)
end

def send_consul_deploy(application:, environment:, sender:, source:)
  application, environment, sender, source = [Shellwords.escape(application), Shellwords.escape(environment), Shellwords.escape(sender), Shellwords.escape(source)]

  deploy = "#{application}-#{environment}-deploy"
  payload = "#{sender} #{source}"
  puts %Q(Processing deploy command: #{deploy} #{payload})

  consul = `which consul`.chomp
  # Try deploying first with a datacenter, then without
  raise "Could not send deploy command!" unless
    system(%Q(#{consul} event -datacenter="#{environment}" -name="#{deploy}" "#{payload}")) ||
    system(%Q(#{consul} event -name="#{deploy}" "#{payload}"))

  puts "Deploy event fired!"
end
