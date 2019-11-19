# ------------------------------------------------------------------------------
# Copyright (c) 2006-2012 Novell, Inc. All Rights Reserved.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

# Module:  update_proposal.ycp
#
# Author:  Arvin Schnell <arvin@suse.de>
#
# Purpose:  Let user choose update settings.
#

require "cgi/util"
require "y2packager/product_upgrade"
require "y2packager/resolvable"

module Yast
  class UpdateProposalClient < Client
    include Yast::Logger

    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "update"

      Yast.import "HTML"
      Yast.import "Update"
      Yast.import "RootPart"
      Yast.import "Packages"
      Yast.import "PackageCallbacks"
      Yast.import "SpaceCalculation"

      Yast.import "Installation"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "ProductFeatures"
      Yast.import "Product"
      Yast.import "FileUtils"
      Yast.import "Label"
      Yast.import "Stage"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      @rpm_db_existency_checked_already = false

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        # call some function that makes a proposal here:
        #
        # DummyMod::MakeProposal( force_reset );

        if @force_reset
          Update.Reset
          Packages.Reset([:product])
          Update.did_init1 = false
          @rpm_db_existency_checked_already = false
        end

        # bugzilla #148105
        if !@rpm_db_existency_checked_already
          @rpm_db_existency_checked_already = true

          # if it doesn't exist, user can still confirm to continue
          # packager will then suggest some set of packages
          if !CheckRPMDBforExistency()
            return {
              # error message in proposal
              "warning"       => _(
                "Cannot read the current RPM Database."
              ),
              "warning_level" => :fatal,
              "raw_proposal"  => []
            }
          end
        end

        # Fill return map

        init_stuff

        # TRANSLATORS: unknown product (label)
        @update_from = _("Unknown product")
        if Ops.get_string(Installation.installedVersion, "show", "") != "" &&
            Ops.get_string(Installation.installedVersion, "show", "?") != "?"
          @update_from = Ops.get_string(
            Installation.installedVersion,
            "show",
            ""
          )
        elsif Ops.get_string(Installation.installedVersion, "version", "") != "" &&
            Ops.get_string(Installation.installedVersion, "version", "?") != "?"
          @update_from = Ops.get_string(
            Installation.installedVersion,
            "name",
            ""
          )
        end

        # TRANSLATORS: unknown product (label)
        @update_to = _("Unknown product")
        if Ops.get_string(Installation.updateVersion, "show", "") != ""
          @update_to = Ops.get_string(Installation.updateVersion, "show", "")
        elsif Ops.get_string(Installation.updateVersion, "version", "") != ""
          @update_to = Ops.get_string(Installation.updateVersion, "name", "")
        end

        if Update.products_incompatible
          return {
            # error message in proposal
            "warning"       => format(
              _(
                "The installed product (%{update_from}) is not compatible with " \
                "the product on the installation media (%{update_to})."
              ),
              update_from: @update_from, update_to: @update_to
            ),
            "warning_level" => :fatal,
            "raw_proposal"  => []
          }
        end

        # when versions don't match and upgrade is not allowed (running system)
        if Ops.get_string(Installation.installedVersion, "version", "A") !=
            Ops.get_string(Installation.updateVersion, "version", "B") &&
            Update.disallow_upgrade
          return {
            "warning"       => Builtins.sformat(
              # TRANSLATORS: proposal error, %1 is the version of installed system
              # %2 is the version being installed
              _(
                "Updating system to another version (%1 -> %2) is not supported on " \
                  "the running system.<br>\n" \
                  "Boot from the installation media and use a normal upgrade\n" \
                  "or disable software repositories of products with different versions.\n"
              ),
              @update_from,
              @update_to
            ),
            "warning_level" => :fatal,
            "raw_proposal"  => []
          }
        end

        @warning_message = ""

        # when labels don't match
        if !Stage.initial &&
            Ops.get_string(Installation.installedVersion, "show", "A") !=
                Ops.get_string(Installation.updateVersion, "show", "B")
          @warning_message = Builtins.sformat(
            # TRANSLATORS: proposal warning, both %1 and %2 are replaced with product names
            _(
              "Warning: Updating from '%1' to '%2', products do not exactly match."
            ),
            Ops.get_locale(
              # TRANSLATORS: unknown product name
              Installation.installedVersion,
              "show",
              _("Unknown product")
            ),
            Ops.get_locale(
              # TRANSLATORS: unknown product name
              Installation.updateVersion,
              "show",
              _("Unknown product")
            )
          )
        end

        products = Y2Packager::Resolvable.find(kind: :product)
        # stores the proposal text output
        @summary_text = Packages.product_update_summary(products)
          .map { |item| "<li>#{item}</li>" }.join

        # recalculate the disk space usage data
        SpaceCalculation.GetPartitionInfo

        # TRANSLATORS: proposal dialog help
        @update_options_help = _(
          "<p><b><big>Update Options</big></b> Select how your system will be updated.\n" \
            "Choose if only installed packages should be updated or new ones should be\n" \
            "installed as well (default). Decide whether unmaintained packages should be\n" \
            "deleted.</p>\n"
        )

        @ret = {
          "preformatted_proposal" => Ops.add(
            Ops.add(HTML.ListStart, @summary_text),
            HTML.ListEnd
          ),
          "help"                  => @update_options_help
        }

        product_warning = Packages.product_update_warning(products)
        @warning_message << product_warning["warning"] if product_warning["warning"]

        if !@warning_message.empty?
          @ret["warning"] = @warning_message
          @ret["warning_level"] = product_warning["warning_level"] || :warning
        end
        # save the solver test case with details for later debugging
        Pkg.CreateSolverTestCase("/var/log/YaST2/solver-upgrade-proposal") if @ret["warning"]
      elsif @func == "AskUser"
        # With proper control file, this should never be reached
        Report.Error(_("The update summary is read only and cannot be changed."))
        @ret = { "workflow_sequence" => :back }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Update Options"),
          # this is a menu entry
          "menu_title"      => _("&Update Options"),
          "id"              => "update_stuff"
        }
      end

      deep_copy(@ret)
    end

    # Function returns map of upgrade-configuration.
    # Some keys might be missing. In that case, the default libzypp
    # values will be used. See FATE #301990 and bnc #238488.
    # The keys should be matching keys for Pkg::PkgUpdateAll().
    # "keep_installed_patches" were removed by bnc #349533.
    #
    # @return [Hash{String => Object}] with a configuration
    #
    #
    # **Structure:**
    #
    #     $[
    #          "delete_unmaintained" : boolean,
    #          "silent_downgrades" : boolean,
    #      ]
    def GetUpdateConf
      # 'nil' values are skipped, in that case, ZYPP uses own default values
      ret = {}

      # not supported by libzypp anymore
      #  if (Update::deleteOldPackages != nil) {
      #      ret["delete_unmaintained"] = Update::deleteOldPackages;
      #  }

      if !Update.silentlyDowngradePackages.nil?
        Ops.set(ret, "silent_downgrades", Update.silentlyDowngradePackages)
      end

      Builtins.y2milestone("Using update configuration: %1", ret)

      deep_copy(ret)
    end

    # bugzilla #148105
    # Check the current RPM Database if exists
    #
    # RPM DB found -> return true
    # RPM DB not found & skipped -> return true
    # RPM DB not found & aborted -> return false
    #
    def CheckRPMDBforExistency
      Builtins.y2milestone(
        "Checking the current RPM Database in '%1'...",
        Installation.destdir
      )

      # at least one must be there, the second one is for RPM v3
      rpm_db_files = ["/var/lib/rpm/Packages", "/var/lib/rpm/packages.rpm"]
      ret = false
      file_found_or_error_skipped = false

      until file_found_or_error_skipped
        Builtins.foreach(rpm_db_files) do |check_file|
          if Installation.destdir != "/"
            check_file = Builtins.sformat(
              "%1%2",
              Installation.destdir,
              check_file
            )
          end
          if FileUtils.Exists(check_file)
            Builtins.y2milestone("RPM Database '%1' found", check_file)
            ret = true
            file_found_or_error_skipped = true
            raise Break
          end
        end

        # file not found
        next if ret

        Builtins.y2error(
          "None of files %1 exist in '%2'",
          rpm_db_files,
          Installation.destdir
        )

        missing_files = ""
        Builtins.foreach(rpm_db_files) do |check_file|
          if Installation.destdir != "/"
            check_file = Builtins.sformat(
              "%1%2",
              Installation.destdir,
              check_file
            )
          end
          missing_files = Ops.add(Ops.add(missing_files, "\n"), check_file)
        end

        UI.OpenDialog(
          Opt(:decorated),
          VBox(
            # popup error
            Label(
              Ops.add(
                Ops.add(
                  # part of error popup message
                  _("Cannot read the current RPM Database.") + "\n\n",
                  # part of error popup message, %1 stands for newline-separated list of files
                  Builtins.sformat(
                    _("None of these files exist:%1"),
                    missing_files
                  )
                ),
                "\n\n"
              )
            ),
            HBox(
              PushButton(Id(:abort), Label.AbortButton),
              # disabled button - bugzilla #148105, comments #22 - #28
              # `PushButton (`id(`ignore), Label::IgnoreButton())
              PushButton(Id(:retry), Label.RetryButton)
            )
          )
        )

        ui_r = UI.UserInput

        if ui_r == :cancel || ui_r == :abort
          ret = false
          file_found_or_error_skipped = true
          Builtins.y2milestone("Check failed, returning error.")
        elsif ui_r == :retry
          file_found_or_error_skipped = false
          Builtins.y2milestone("Trying again...")
          # } else if (ui_r == `ignore) {
          #    ret = true;
          #    file_found_or_error_skipped = true;
          #    y2warning ("Skipping missing RPM Database, problems might occur...");
        else
          file_found_or_error_skipped = false
          Builtins.y2error("Unexpected return: %1", ui_r)
        end

        UI.CloseDialog
      end

      Builtins.y2milestone("CheckRPMDBforExistency - returning: %1", ret)
      ret
    end

    def init_stuff
      # initialize package manager
      Packages.Init(true)

      # initialize target
      PackageCallbacks.SetConvertDBCallbacks

      Pkg.TargetInit(Installation.destdir, false)

      Update.GetProductName

      # FATE #301990, Bugzilla #238488
      # Set initial update-related (packages/patches) values from control file
      Update.InitUpdate

      # some products are listed in media control file and at least one is compatible
      # with system just being updated
      update_not_possible = false

      # FATE #301844
      Builtins.y2milestone(
        "Previous '%1', New '%2' RootPart",
        RootPart.previousRootPartition,
        RootPart.selectedRootPartition
      )
      if RootPart.previousRootPartition != RootPart.selectedRootPartition
        RootPart.previousRootPartition = RootPart.selectedRootPartition

        # check whether update is possible
        # reset configuration in respect to the selected system
        Update.Reset
        if !Update.IsProductSupportedForUpgrade
          Builtins.y2milestone("Upgrade is not supported")
          update_not_possible = true
        end
      end

      # connect target with package manager
      if !Update.did_init1
        Update.did_init1 = true

        # products to reselect after reset
        restore = []

        Y2Packager::Resolvable.find(kind: :product).each do |product|
          # only selected items but ignore the selections done by solver,
          # during restoration they would be changed to be selected by YaST and they
          # will be selected by solver again anyway
          restore << product.name if product.status == :selected && product.transact_by != :solver
        end

        Pkg.PkgApplReset

        # bnc #300540
        # bnc #391785
        # Drops packages after PkgApplReset, not before (that would null that)
        Update.DropObsoletePackages

        Builtins.foreach(restore) { |res| Pkg.ResolvableInstall(res, :product) }

        # install the needed package (e.g. "cifs-mount" for SMB or "nfs-client"
        # for NFS repositories or "grub2" for the bootloader)
        # false = allow installing new packages, otherwise it would only upgrade
        # the already installed packages
        Packages.SelectSystemPackages(false)

        # FATE #301990, Bugzilla #238488
        # Control the upgrade process better
        update_sum = Pkg.PkgUpdateAll(GetUpdateConf())
        Builtins.y2milestone("Update summary: %1", update_sum)

        # deselect the upgraded obsolete products (bsc#1133215)
        Y2Packager::ProductUpgrade.remove_obsolete_upgrades

        Update.unknown_packages = Ops.get(update_sum, :ProblemListSze, 0)
      end

      # preselect system patterns (including PackagesProposal patterns)
      sys_patterns = Packages.ComputeSystemPatternList
      sys_patterns.each { |pat| Pkg.ResolvableInstall(pat, :pattern) }

      Update.solve_errors = Pkg.PkgSolve(false) ? 0 : Pkg.PkgSolveErrors

      log.info "Update compatibility: " \
        "Update.ProductsCompatible: #{Update.ProductsCompatible}, " \
        "Update.products_incompatible: #{Update.products_incompatible}, " \
        "update_not_possible: #{update_not_possible}"

      # check product compatibility
      if !(Update.ProductsCompatible || Update.products_incompatible) || update_not_possible
        if Popup.ContinueCancel(
          # continue-cancel popup
          _(
            "The installed product is not compatible with the product\n" \
              "on the installation media. If you try to update using the\n" \
              "current installation media, the system may not start or\n" \
              "some applications may not run properly."
          )
        )
          Update.IgnoreProductCompatibility
        else
          Update.products_incompatible = true
        end
      end

      nil
    end
  end
end

Yast::UpdateProposalClient.new.main
