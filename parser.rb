require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'byebug'
  gem 'write_xlsx'
  gem 'roo'
  gem 'httparty'
  gem 'tty-prompt'
  gem 'whirly'
  gem 'paint'
end

class Parser
  API_KEY = ENV['SICKW_API_KEY']
  
  SICKW_BASE_URL           = "https://sickw.com/api.php"
  SICKW_API_KEY_VALIDATION = /((\d|\w){3}-?){8}/i
  SICKW_SERVICES           = [{ code: 30, name: 'Apple Basic Info', price: '0.10' }]
  DEFAULT_SICKW_SERVICE    = SICKW_SERVICES.first[:code]
  
  def initialize
    @prompt      = TTY::Prompt.new
    @result_rows = []
  end

  def run
    @user_data = collect_user_data
    @prompt.ok('')
  
    price     = SICKW_SERVICES.find { |service_hash| service_hash[:code] == @user_data[:service] }[:price]
    cost      = imeis.size * BigDecimal(price)
    formatted = sprintf('%.2f', cost)
    proceed   = @prompt.yes?("Run will cost $#{formatted}. Proceed?")
    return @prompt.say('Shutting down...') unless proceed
    
    Whirly.start(spinner: 'random_dots', status: 'Starting up...')
    sleep 1
    parse_rows
  end

  def balance
    Whirly.status = 'Refreshing balance'
    sleep 2
    response      = HTTParty.get(SICKW_BASE_URL + '?format=json&key=DZ3-DZL-72K-BLW-T65-8FB-VK1-IW4&imei=354442067957452&service=demo')
    JSON.parse(response)['balance']
  end

  private

  def collect_user_data
    bal = balance
    @prompt.collect do
      key(:api_key).mask("Please enter your Sickw api key") do |answer|
        answer.default API_KEY
        answer.validate SICKW_API_KEY_VALIDATION, 'Api Key must be 24 characters (excluding dashes)'
      end
      @prompt.ok "Your balance is $#{bal}"
      if ARGV[0].nil?
        key(:path).ask("Please enter the path to your file", required: true)
      else
        @answers[:path] = ARGV[0]
      end
      key(:service).select("Select a service") do |menu|
        menu.enum "."
        SICKW_SERVICES.each do |service_hash|
          menu.choice "#{service_hash[:name]} - $#{service_hash[:price]}", service_hash[:code]
        end
      end
    end
  end
  
  def parse_rows
    imeis.each do |imei|
      Whirly.status = 'Hitting up Sickw'
      sleep 1
      response = call_sickw(imei)
      if response['status'] === 'success'
        @result_rows << parse_response(response).map{|field, val | val.gsub(/<\/?[^>]*>/, "")}
      elsif response['status']&.match('rejected|error|request-error')
        @result_rows << [imei, response['result'], response['status']]
      else
        @result_rows << [imei, response['result'], response['status']]
      end
    end
    export
  end
  
  def imeis
    CSV.read(@user_data[:path]).flatten
  end
  
  def call_sickw(imei)
    Whirly.status = 'Waiting on Sickw for ' + imei
    response = HTTParty.get(SICKW_BASE_URL, { query: query_params(imei) })
    parsed   = JSON.parse(response.body)
    puts log_output(parsed, imei)
    parsed
  rescue StandardError => e
    { 'status': 'request-error', 'result': e }
  end
  
  def log_output(parsed_response, imei)
    if parsed_response['status'] == 'success'
      "SUCCESS: #{imei}                                            "
    else
      [parsed_response['status'].upcase, imei, parsed_response['result']].join(' - ')
    end
  end
  
  def query_params(imei)
    {
      format:  'json',
      key:     API_KEY,
      service: @user_data.fetch(:service, DEFAULT_SICKW_SERVICE),
      imei:    imei
    }
  end
  
  def parse_response(response_data)
    imageless_fields = response_data['result'].split('<br />')[1..-1]
    fields_map = imageless_fields.map { |data_field| data_field.split(':') }.to_h
    @headers ||= fields_map.keys
    fields_map
  rescue StandardError => e
    p e
  end
  
  def export
    path = './outputs/results.csv'
    Whirly.status = "Exporting to #{path.sub('.', Dir.pwd)}"
    sleep 2
    csv = CSV.open(path, 'wb')
    csv << @headers
    @result_rows.each do |row|
      begin
        csv << (row.is_a?(Hash) ? row.values : row)
      rescue StandardError => e
        puts e
        csv << ["ERROR: #{e}"]
      end
    end
    Whirly.status = ''
    Whirly.stop
    puts 'Operation completed successfully'
  end

end

Parser.new.run

