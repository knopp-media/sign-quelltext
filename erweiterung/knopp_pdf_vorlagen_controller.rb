# frozen_string_literal: true

# Knopp Media Sign: legt aus einem hochgeladenen PDF mit fertig gesetzten Feldern eine Vorlage an
# (für „Dokument hochladen“ im Vertragsassistenten). Ersatz für /api/templates/pdf, das es nur in der
# Bezahlversion gibt. Gleiche Schritte wie deploy/vorlage_anlegen.rb. Eingebunden per Compose als
# app/controllers/api/knopp_pdf_vorlagen_controller.rb, Route in config/initializers/knopp_routen.rb.
#
# POST /api/knopp/pdf_vorlagen (X-Auth-Token), JSON (DocuSeal liest unter /api alles als JSON):
#   { "pdf": "<base64>", "name": "...", "folder_name": "...", "submitters": [{name, uuid}], "fields": [...] }
#   Felder mit Bereichen ohne attachment_uuid, die setzt dieser Endpunkt.
module Api
  class KnoppPdfVorlagenController < ApiBaseController
    MAX_GROESSE = 20.megabytes

    def create
      authorize!(:create, Template)

      daten = JSON.parse(request.raw_post)
      pdf = Base64.strict_decode64(daten['pdf'].to_s)
      return fehler('Bitte ein PDF hochladen.') unless pdf.start_with?('%PDF')
      return fehler('Das PDF ist zu groß.') if pdf.bytesize > MAX_GROESSE

      rollen = Array(daten['submitters'])
      felder = Array(daten['fields'])
      name = daten['name'].to_s.strip.presence || 'Dokument'

      vorlage = Template.new(account: current_account, author: current_user, name: name.first(200),
                             folder: TemplateFolders.find_or_create_by_name(current_user, daten['folder_name'].presence || 'Hochgeladen'),
                             submitters: rollen, fields: [], schema: [], source: :api)
      Templates.maybe_assign_access(vorlage)
      vorlage.save!

      datei = Tempfile.new(['dokument', '.pdf'], binmode: true)
      datei.write(pdf)
      datei.rewind
      hochgeladen = ActionDispatch::Http::UploadedFile.new(tempfile: datei, filename: "#{name.parameterize.presence || 'dokument'}.pdf",
                                                           type: 'application/pdf')
      dokumente, = Templates::CreateAttachments.call(vorlage, { files: [hochgeladen] }, extract_fields: false)
      dokument = dokumente.first
      felder.each { |f| Array(f['areas']).each { |a| a['attachment_uuid'] = dokument.uuid } }
      vorlage.update!(fields: felder, schema: [{ 'attachment_uuid' => dokument.uuid, 'name' => vorlage.name }])

      render json: { id: vorlage.id, name: vorlage.name }
    rescue JSON::ParserError, ArgumentError
      fehler('Anfrage nicht lesbar.')
    rescue Templates::CreateAttachments::PdfEncrypted
      fehler('Das PDF ist mit einem Passwort geschützt.')
    ensure
      datei&.close!
    end

    private

    def fehler(text)
      render json: { error: text }, status: :unprocessable_content
    end
  end
end
