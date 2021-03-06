require 'gcm'
require 'base64'
require 'json'
require 'securerandom'
require 'sinatra'
require 'rest-client'
require './models/device'
require './models/look'
require './models/user'
require './models/vote'
require './config/environments'
require './constants'


require 'pry'

configure do
  set :bind, '0.0.0.0'
end

get '/' do
  'Hello world!'
end

get '/looks/' do
  content_type :json
  request_user_id = params['request_user_id']  # We don't want a user to be able to see his own looks
  date_range_filter = DateTime.now..(DateTime.now + 5.years)  
  Look.all.where(expiration: date_range_filter).where.not(user_id: request_user_id).reverse.to_json({include: :user, methods: :vote_results})
end

post '/looks/' do
  content_type :json

  puts params.keys

  expiration = params['expiration']
  image_string = params['image_string']
  quote = params['quote']
  user_id = params['user_id']
  
  filename = SecureRandom.hex + '.png' # just using random filenames for now, should be ids
  file_location = "./public/#{LOOK_IMAGE_PATH}/" + filename

  File.open(file_location, 'w') do |new_file|
    new_file.write Base64.decode64(image_string)
  end
  
  look = Look.create(image_url: "/looks/#{filename}", user_id: user_id, expiration: expiration, type_index: 0, quote: quote)
  
  look.to_json
end

get "/:filename" do |filename|
  content_type "image/*"
end

get "/#{USER_THUMBNAIL_PATH}/:filename" do |filename|
  content_type "image/*"
end

get "/#{USER_BANNER_PATH}/:filename" do |filename|
  content_type "image/*"
end

get "/#{LOOK_IMAGE_PATH}/:filename" do |filename|
  content_type "image/*"
end

get '/users/' do
  content_type :json
  @users = User.all.to_json
end

post '/users/' do
  content_type :json
  data = JSON.parse request.body.read
  user = User.create(name: data['name'], profile_image: "#{USER_THUMBNAIL_PATH}/" + data['profile_image'])
  user.to_json
end

get '/users/:id/' do
  content_type :json
  user = User.find(params['id']).to_json({
    include: [{looks: {
      methods: :vote_results
    }}]
  })
end

get '/me/' do
  content_type :json
  User.where(name: "Ryan").first.to_json
end

delete '/users/:id/' do
  content_type :json
  User.delete(params['id'])
  {message: 'Success!'}.to_json
end

post '/looks/:look_id/votes/' do
  content_type :json

  look_id = params['look_id']
  Vote.create(user_id: params['user_id'], look_id: params['look_id'], value: params['vote'])
  
  look = Look.find(look_id)
  
  if should_send_push?(look)
      devices = Device.where(user_id: look.user_id)
      send_push_for_devices(devices)
  end
  
  {message: 'The vote was successfully cast!'}.to_json
end

delete '/looks/:id/' do
  content_type :json
  Look.delete(params['id'])
  {message: 'Success!'}.to_json
end

get '/looks/:look_id/votes/' do
  content_type :json
  Look.find(params[:look_id]).votes.to_json
end

get '/reset_db/' do
  content_type :json
  require './scripts/populate_demo_data'
  {message: 'The db was successfully reset'}.to_json
end


# TODO helpers. Move this
def should_send_push?(look)
  look.votes.count > 25 || look.is_expired?
end

def send_push_for_devices(devices)
  reg_tokens = devices.map do |device|
    device.reg_token
  end
  if reg_tokens.count != 0
    print "Sending gcm message!"
    send_gcm_message(params[:title], params[:body], reg_tokens)
  end  
end


# PUSH NOTIFICATIONS

# Registration endpoint mapping reg_token to user_id
# POST /register-device?reg_token=abc&user_id=123
post '/register-device/' do
  content_type :json
  reg_token = params[:reg_token]
  user_id = params[:user_id]
  device = Device.where(user_id: user_id).first
    
  if device
    device.reg_token = reg_token
  device.save
  else
    device = Device.create(reg_token: reg_token, user_id: user_id)
  end
    
  device.to_json
end

get '/destroy-all-devices/' do
  Device.destroy_all
  {message: 'Success!'}.to_json
end

# Endpoint for sending a message to a user
# POST /send?user_id=123&title=hello&body=message
post '/send/' do
  # Find devices with the corresponding reg_tokens
  devices = Device.where(:user_id => params[:user_id])
  send_push_for_devices(devices)
end

get '/push-ryan/' do
    content_type :json
    ryan = User.where(name: "Ryan").first
    devices = Device.where(user_id: ryan.id)
    send_push_for_devices(devices)
    {message: 'Sending a push to Ryan'}.to_json
end



get '/send-fake-push/' do
  gcm = GCM.new("AIzaSyDu3W-FnpvKH_U7CG3wYoQTvY_Su67t0s4")
  reg_tokens = ["fP6-4ytom4I:APA91bF7G1yCOSCTYZKlDwn1qg3FncfL_ixYxBcF7L-BthpnCUQiufDhaYsdVG11bMZscdFcWOYlI4knRqLlK26UkM3CkJEBjXD3lSGxzOt68gyV0XZes-ZJNuWO8-ihfnHot5GEmD9s"]
  options = { :notification => { :title => "Your look has been voted on", :body => "Go check it out" } }
  response = gcm.send(reg_tokens, options)
  {message: 'Success!'}.to_json
end

get '/devices/' do
  content_type :json
  Device.all.to_json
end


# Sending logic
# send_gcm_message(["abc", "cdf"])
def send_gcm_message(title, body, reg_tokens)
  # Construct JSON payload
  post_args = {
    # :to field can also be used if there is only 1 reg token to send
    :registration_ids => reg_tokens,
    :notification => {
      :title  => "You look has been voted on",
      :body => "Check out the results!"
    }
  }
  
  print post_args 

  # Send the request with JSON args and headers
  RestClient.post 'https://gcm-http.googleapis.com/gcm/send', post_args.to_json,
    :Authorization => 'key=AIzaSyC0EVhbTNqgr69Pr8pWEdPDe5SSSIWhaU0', :content_type => :json, :accept => :json
end
