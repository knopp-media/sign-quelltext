# frozen_string_literal: true

# Knopp Media Sign: Route für den eigenen PDF-Endpunkt (siehe app/controllers/api/knopp_pdf_vorlagen_controller.rb).
# prepend, damit sie vor DocuSeals Fehlerseite für /api/... greift.
Rails.application.routes.prepend do
  post '/api/knopp/pdf_vorlagen', to: 'api/knopp_pdf_vorlagen#create', defaults: { format: :json }
  get '/api/knopp/verlauf/:id', to: 'api/knopp_pdf_vorlagen#verlauf', defaults: { format: :json }
end
