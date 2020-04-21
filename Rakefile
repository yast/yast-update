require "yast/rake"

Yast::Tasks.submit_to :sle15sp2
require "shellwords"

Yast::Tasks.configuration do |conf|
  # lets ignore license check for now
  conf.skip_license_check << /.*/

  conf.install_locations["control/*.xml"] = Packaging::Configuration::YAST_DIR + "/control/"
end

# additionally validate the control XML files as a part of the unit tests
task "test:unit" do
  sh "xmllint --noout --relaxng #{Packaging::Configuration::YAST_DIR.shellescape}"\
    "/control/control.rng control/*.xml"
end
