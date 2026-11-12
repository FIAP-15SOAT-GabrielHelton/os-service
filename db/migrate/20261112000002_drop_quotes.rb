# Orçamentos passaram a pertencer ao billing-service (RFC-005).
class DropQuotes < ActiveRecord::Migration[8.1]
  def up
    drop_table :quote_line_items
    drop_table :quotes
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
