class CreateDevices < ActiveRecord::Migration
  def change
    create_table :devices do |t|
      t.integer :user_id
      t.string :reg_token
      t.string :os, default: 'android'
    end
  end
end
