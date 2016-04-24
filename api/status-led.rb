require "net/http"
require "json"
require "mongo"

before '/api/*' do
  @y_app_id = ENV['YAHOO_API_TOKEN']
  
  client = Mongo::Client.new([ENV['MONGO_LOCAL_ADDRESS']],
    :database => 'statusled',
        :user => 'statusled',
    :password => ENV['MONGO_STATUSLED_PASS']
  )
  @devices = client[:devices]
end

get '/api/status-led/get' do
  content_type 'text/plain'
  
  device = @devices.find(:device_id => params['device_id']).to_a.first.to_h
  
  if device == {}
    status 404
    return "device not found (id: #{params['device_id']})"
  end
  
  colors = device["rules"].map.with_index {|rule, i| get_status_color(device, i) }.compact
  
  if 0 < colors.count then
    return "1" + colors.reduce("") {|tmp, color| tmp + color }
  else
    return "0"
  end
end

helpers do
  def get_status_color(device, i)
    rule = device["rules"][i]
    case rule["label"]
      
      when 'weather'
        weather = get_weather(rule["zipcode"])
        # 郵便番号から取得した住所を保存
        device["rules"][i]["location"] = weather[:location]
        @devices.find_one_and_replace({"device_id" => device["device_id"]}, device)
        # 降水確率を判定し結果を返す
        if 0 < weather[:rainfall] then
          return convert_brightness(rule["brightness"]) + generate_color_str(rule["color"])
        end
        return nil
        
      when 'train'
        if get_train_status(rule["train"]) then
          return convert_brightness(rule["brightness"]) + generate_color_str(rule["color"])
        end
        return nil
        
    end
  end
  def get_weather(zipcode)
    # 郵便番号から経度緯度を取得する
    geo = get_geo_by_zipcode(zipcode)
    
    # 住所（Array）は町名（3要素目）までを1つの文字列に変換する
    address = get_address_by_geo(geo[:lat], geo[:lon])
    location = address.shift(3).reduce { |tmp, item| tmp + item }
    
    # 直近1時間の降水確率を合計する
    weather = get_weather_by_geo(geo[:lat], geo[:lon])
    rainfall = weather.reduce(0) { |tmp, item| tmp + item["Rainfall"].to_i }
    
    return {
      :location => location,
      :rainfall => rainfall
    }
  end
  def get_geo_by_zipcode(zipcode)
    host = "search.olp.yahooapis.jp"
    uri = "/OpenLocalPlatform/V1/zipCodeSearch?query=#{zipcode}&detail=simple&appid=#{@y_app_id}&output=json"
    res = Net::HTTP.start(host) {|http| http.get uri}
    data = JSON.parse(res.body)
    geo = data["Feature"][0]["Geometry"]["Coordinates"].split(",")
    geo = [[:lon,:lat],geo].transpose
    geo = Hash[*geo.flatten]
    return geo
  end
  def get_address_by_geo(lat, lon)
    host = "placeinfo.olp.yahooapis.jp"
    uri = "/V1/get?lon=#{lon}&lat=#{lat}&appid=#{@y_app_id}&output=json"
    res = Net::HTTP.start(host) {|http| http.get uri}
    data = JSON.parse(res.body)
    address = data["ResultSet"]["Address"]
    return address
  end
  def get_weather_by_geo(lat, lon)
    host = "weather.olp.yahooapis.jp"
    uri = "/v1/place?coordinates=#{lon},#{lat}&appid=#{@y_app_id}&output=json"
    res = Net::HTTP.start(host) {|http| http.get uri}
    data = JSON.parse(res.body)
    weather = data["Feature"][0]["Property"]["WeatherList"]["Weather"]
    return weather
  end
  def get_train_status(train)
    uri = URI.parse("https://rti-giken.jp/fhc/api/train_tetsudo/delay.json")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    res = http.get(uri.request_uri)
    data = JSON.parse(res.body)
    data.each do |item|
      if item["name"] == train then
        return true
      end
    end
    return false
  end
  def convert_brightness(brightness)
    brightness *= ( 255 / 100.0 )
    brightness = (255 < brightness) ? 255 : brightness.round
    return "%03d" % brightness
  end
  def generate_color_str(rgb)
    r = "%03d" % rgb[0,2].hex
    g = "%03d" % rgb[2,2].hex
    b = "%03d" % rgb[4,2].hex
    return r + g + b
  end
end

