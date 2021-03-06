class Flickr::Client
  attr_reader :connection

  def initialize
    logger = Logger.new("#{Rails.root}/log/flickr.log")
    logger.level = Logger::DEBUG

    @connection = Faraday.new(:url => 'https://api.flickr.com') do |faraday|
      faraday.response :logger, logger
      faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
    end
  end

  def get(conditions)
    response = connection.get('/services/rest', build_conditions(conditions))
    response.body
  end

  private

  def build_conditions(conditions)
    default_conditions.deep_merge!(conditions)
  end

  def default_conditions
    {
      :api_key => Rails.application.secrets[:api_keys][:flickr],
      :format => 'json',
      :nojsoncallback => 1
      #shared_secret: Rails.application.secrets[:api_keys][:flickr_secret]
    }
  end
end
