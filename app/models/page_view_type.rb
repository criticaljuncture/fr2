class PageViewType < ActiveHash::Base
  include ActiveHash::Enum
  enum_accessor :identifier

  self.data = [
    {
      id: 1,
      identifier:         'document',
      cache_expiry_urls:  ['/api/v1/documents', '/documents/'],
      current_as_of:      'doc_counts:current_as_of',
      document_number_position_index: 5,
      filter_expressions: ["^/(documents/|articles/)"],
      google_analytics_url_regex: /^\/(articles|documents)\//,
      historical_set:     "doc_counts:historical",
      namespace:          'doc_counts',
      temp_set:            "doc_counts:in_progress",
      today_set:           "doc_counts:today",
      yesterday_set:      "doc_counts:yesterday",
    },
    {
      id: 2,
      identifier:     'public_inspection_document',
      cache_expiry_urls:  ['/api/v1/public-inspection-documents', '/public-inspection/'],
      current_as_of:  'public_inspection_doc_counts:current_as_of',
      document_number_position_index: 2,
      filter_expressions: ["^/(public_inspection_documents/.*/.*/.*/.*/.*|public-inspection/[12][0-9][0-9][0-9]-)"],
      google_analytics_url_regex: /^\/(public_inspection_documents\/.*\/.*\/.*\/.*\/.*|public-inspection\/\d{4}-.*\/.*)/,
      historical_set: "public_inspection_doc_counts:historical",
      namespace:       'public_inspection_doc_counts',
      temp_set:        "public_inspection_doc_counts:in_progress",
      today_set:       "public_inspection_doc_counts:today",
      yesterday_set:  "public_inspection_doc_counts:yesterday",
    },
  ]

end
