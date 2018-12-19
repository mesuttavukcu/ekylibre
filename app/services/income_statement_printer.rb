# This object allow printing the general ledger
class IncomeStatementPrinter
  include PdfPrinter

  def initialize(options)
    @document_nature = Nomen::DocumentNature.find(options[:document_nature])
    @key             = options[:key]
    @template_path   = find_open_document_template(options[:document_nature])
    @params          = options[:params]
    @financial_year  = options[:financial_year]
  end

  def compute_dataset
    dataset = []
    document_scope = :profit_and_loss_statement
    current_compute = AccountancyComputation.new(@financial_year)
    previous_compute = AccountancyComputation.new(@financial_year.previous)
      # products
      g1 = HashWithIndifferentAccess.new
      g1[:group_name] = "Produits d'exploitation"
      g1[:items] = []
      items = [:products_sales, :animal_sales, :productions_sales,
               :inventory_variations, :capitalised_production, :subsidies,
               :provisions_revenues, :other_products]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g1[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g1.inspect.yellow
      end
      g1[:sum_name] = "Total I"
      g1[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :products_subtotal)
      g1[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :products_subtotal)
      dataset << g1

      # charges
      g2 = HashWithIndifferentAccess.new
      g2[:group_name] = "Charges d'exploitation"
      g2[:items] = []
      items = [:merchandises_purchases, :merchandises_purchases_stocks_variation, :products_purchases,
               :purchases_stocks_variation, :animal_purchases, :other_purchases,
               :taxes, :wages, :social_expenses, :depreciations_inputations_expenses, :other_expenses]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g2[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
      end
      g2[:sum_name] = "Total II"
      g2[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :charges_subtotal)
      g2[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :charges_subtotal)
      g2[:sub_result_name] = "Résultat d'exploitation (I - II)"
      g2[:sub_result_current_value] = current_compute.sum_entry_items_by_line(document_scope, :exploitation_result)
      g2[:sub_result_previous_value] = previous_compute.sum_entry_items_by_line(document_scope, :exploitation_result)
      dataset << g2

      # produits financiers
      g3 = HashWithIndifferentAccess.new
      g3[:group_name] = "Produits financiers"
      g3[:items] = []
      items = [:financial_participations, :financial_debts, :financial_others_interests,
               :financial_depreciations, :financial_positive_change, :financial_net_cession_values]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g3[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g3.inspect.yellow
      end
      g3[:sum_name] = "Total III"
      g3[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :financial_products_subtotal)
      g3[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :financial_products_subtotal)
      dataset << g3

      # charges financieres
      g4 = HashWithIndifferentAccess.new
      g4[:group_name] = "Charges financieres"
      g4[:items] = []
      items = [:financial_asset_dotations, :financial_interests_and_charges,
               :financial_negative_change, :financial_net_cession_debts]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g4[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g4.inspect.yellow
      end
      g4[:sum_name] = "Total IV"
      g4[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :financial_expenses_subtotal)
      g4[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :financial_expenses_subtotal)
      g4[:sub_result_name] = "Résultat financier (III - IV)"
      g4[:sub_result_current_value] = current_compute.sum_entry_items_by_line(document_scope, :financial_result)
      g4[:sub_result_previous_value] = previous_compute.sum_entry_items_by_line(document_scope, :financial_result)
      dataset << g4

      g5 = HashWithIndifferentAccess.new
      g5[:group_name] = ""
      g5[:items] = []
      g5[:sub_result_name] = "Résultat courant avant impôts (I - II - III - IV)"
      g5[:sub_result_current_value] = current_compute.sum_entry_items_by_line(document_scope, :before_taxe_result)
      g5[:sub_result_previous_value] = previous_compute.sum_entry_items_by_line(document_scope, :before_taxe_result)
      dataset << g5

      # produits exceptionnelles
      g6 = HashWithIndifferentAccess.new
      g6[:group_name] = "Produits exceptionnels"
      g6[:items] = []
      items = [:exceptional_products_on_management_operations, :exceptional_products_on_assets_cessions,
               :exceptional_products_on_capital_operations, :exceptional_products_on_provisions]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g6[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g6.inspect.yellow
      end
      g6[:sum_name] = "Total V"
      g6[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :exceptional_products_subtotal)
      g6[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :exceptional_products_subtotal)
      dataset << g6

      # charges exceptionnelles
      g7 = HashWithIndifferentAccess.new
      g7[:group_name] = "Charges exceptionnelles"
      g7[:items] = []
      items = [:exceptional_expenses_on_management_operations, :exceptional_expenses_on_assets_cessions,
               :exceptional_expenses_on_capital_operations, :exceptional_expenses_on_provisions]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g7[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g7.inspect.yellow
      end
      g7[:sum_name] = "Total VI"
      g7[:current_sum] = current_compute.sum_entry_items_by_line(document_scope, :exceptional_expenses_subtotal)
      g7[:previous_sum] = previous_compute.sum_entry_items_by_line(document_scope, :exceptional_expenses_subtotal)
      g7[:sub_result_name] = "Résultat exceptionnel (V - VI)"
      g7[:sub_result_current_value] = current_compute.sum_entry_items_by_line(document_scope, :exceptional_result)
      g7[:sub_result_previous_value] = previous_compute.sum_entry_items_by_line(document_scope, :exceptional_result)
      dataset << g7

      # charges exceptionnelles
      g8 = HashWithIndifferentAccess.new
      g8[:group_name] = ""
      g8[:items] = []
      items = [:employee_involvement, :profit_taxe,
               :products_total, :charges_total]
      items.each do |item|
        current_value = current_compute.sum_entry_items_by_line(document_scope, item)
        previous_value = previous_compute.sum_entry_items_by_line(document_scope, item)
        g8[:items] << {name: item.to_s.l, current_value: current_value, previous_value: previous_value}.with_indifferent_access
        # puts g8.inspect.yellow
      end
      g8[:sum_name] = ""
      g8[:current_sum] = ""
      g8[:previous_sum] = ""
      g8[:sub_result_name] = "Bénéfice ou perte"
      g8[:sub_result_current_value] = current_compute.sum_entry_items_by_line(document_scope, :exercice_result)
      g8[:sub_result_previous_value] = previous_compute.sum_entry_items_by_line(document_scope, :exercice_result)
      dataset << g8

    dataset.compact
  end

  def run_pdf
    dataset = compute_dataset
    # puts dataset.inspect.green

    report = generate_document(@document_nature, @key, @template_path) do |r|

      # build header
      e = Entity.of_company
      company_name = e.full_name
      company_address = e.default_mail_address&.coordinate

      # build filters
      data_filters = []

      # build started and stopped
      started_on = @financial_year.started_on
      stopped_on = @financial_year.stopped_on

      r.add_field 'COMPANY_ADDRESS', company_address
      r.add_field 'DOCUMENT_NAME', @document_nature.human_name
      r.add_field 'FILE_NAME', @key
      r.add_field 'PERIOD', I18n.translate('labels.from_to_date', from: started_on.l, to: stopped_on.l)
      r.add_field 'DATE', Date.today.l
      r.add_field 'STARTED_ON', started_on.to_date.l
      r.add_field 'N', stopped_on.to_date.l
      r.add_field 'N_1', @financial_year.previous.stopped_on.to_date.l
      r.add_field 'PRINTED_AT', Time.zone.now.l(format: '%d/%m/%Y %T')
      r.add_field 'DATA_FILTERS', data_filters * ' | '

      r.add_section('Section1', dataset) do |s|
        s.add_field(:group_name, :group_name)
        s.add_table('Tableau1', :items, header: false) do |t|
          t.add_column(:name) { |item| item[:name] }
          t.add_column(:current_value) { |item| item[:current_value] }
          t.add_column(:previous_value) { |item| item[:previous_value] }
          t.add_column(:variation_value) do |v|
            if v[:previous_value].to_i != 0
              (((v[:current_value] - v[:previous_value]) / v[:previous_value].abs) * 100).round(2)
            end
          end
        end
        s.add_field(:sum_name, :sum_name) if :sum_name?
        s.add_field(:current_sum, :current_sum) if :current_sum?
        s.add_field(:previous_sum, :previous_sum) if :previous_sum?
        s.add_field(:variation_sum) do |v_s|
          if v_s[:previous_sum].to_i != 0
            (((v_s[:current_sum] - v_s[:previous_sum]) / v_s[:previous_sum].abs) * 100).round(2)
          end
        end
        s.add_field(:sub_result_name, :sub_result_name) if :sub_result_name?
        s.add_field(:sub_result_current_value, :sub_result_current_value) if :sub_result_current_value?
        s.add_field(:sub_result_previous_value, :sub_result_previous_value) if :sub_result_previous_value?

      end

    end
    report.file.path
  end

end
