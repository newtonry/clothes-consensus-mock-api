class CreateUsers < ActiveRecord::Migration
  def change
    create_table :users do |t|
      t.string  :name
      t.string :profile_image
      t.string :banner_image
    end
  end
end
