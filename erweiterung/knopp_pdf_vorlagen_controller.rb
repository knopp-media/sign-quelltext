# frozen_string_literal: true

# Knopp Media Sign: legt aus einem hochgeladenen PDF mit fertig gesetzten Feldern eine Vorlage an
# (für „Dokument hochladen“ im Vertragsassistenten). Ersatz für /api/templates/pdf, das es nur in der
# Bezahlversion gibt. Gleiche Schritte wie deploy/vorlage_anlegen.rb. Eingebunden per Compose als
# app/controllers/api/knopp_pdf_vorlagen_controller.rb, Route in config/initializers/knopp_routen.rb.
#
# POST /api/knopp/pdf_vorlagen (X-Auth-Token), multipart: file (PDF), name, folder_name,
#      submitters (JSON [{name, uuid}]), fields (JSON, Bereiche ohne attachment_uuid)
module Api
  class KnoppPdfVorlagenController < ApiBaseController
    MAX_GROESSE = 20.megabytes

    def create
      authorize!(:create, Template)

      datei = params.require(:file)
      return fehler('Bitte ein PDF hochladen.') unless datei.respond_to?(:read) && datei.content_type == 'application/pdf'
      return fehler('Das PDF ist zu groß.') if datei.size > MAX_GROESSE

      rollen = JSON.parse(params.require(:submitters))
      felder = JSON.parse(params.require(:fields))
      name = params[:name].presence || File.basename(datei.original_filename.to_s, '.*').presence || 'Dokument'

      vorlage = Template.new(account: current_account, author: current_user, name: name.first(200),
                             folder: TemplateFolders.find_or_create_by_name(current_user, params[:folder_name].presence || 'Hochgeladen'),
                             submitters: rollen, fields: [], schema: [], source: :api)
      Templates.maybe_assign_access(vorlage)
      vorlage.save!

      dokumente, = Templates::CreateAttachments.call(vorlage, { files: [datei] }, extract_fields: false)
      dokument = dokumente.first
      felder.each { |f| Array(f['areas']).each { |a| a['attachment_uuid'] = dokument.uuid } }
      vorlage.update!(fields: felder, schema: [{ 'attachment_uuid' => dokument.uuid, 'name' => vorlage.name }])

      render json: { id: vorlage.id, name: vorlage.name }
    rescue JSON::ParserError
      fehler('Felder nicht lesbar.')
    rescue Templates::CreateAttachments::PdfEncrypted
      fehler('Das PDF ist mit einem Passwort geschützt.')
    end

    private

    def fehler(text)
      render json: { error: text }, status: :unprocessable_content
    end
  end
end
