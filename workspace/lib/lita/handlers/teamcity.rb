
# lita-teamcity plugin
module Lita
  module Handlers
    # Main handler
    class Teamcity < Handler
      namespace 'Teamcity'
      include ::TeamcityHelper::Misc

      config :site, required: true, type: String
      config :username, required: true, type: String, default: ''
      config :password, required: true, type: String, default: ''
      config :git_uri, required: true, type: String, default: ''
      config :python_script, required: true, type: String, default: ''

      config :context, required: false, type: String, default: ''
      config :format, required: false, type: String, default: 'verbose'
      config :ignore, required: false, type: Array, default: []
      config :rooms, required: false, type: Array

      PR_PATTERN              = /(?<pr>pr[0-9]{1,5})/
      REVISION_PATTERN        = /(?<revision>r[0-9]{1,5})/
      BRANCH_PATTERN          = /(?<branch>[a-zA-Z0-9\_]{1,100})/
      BUILD_ID_PATTERN        = /(?<build_id>[a-zA-Z0-9\_]{1,100})/
      REPO_PATTERN            = /(?<repo>.+)/
      BUILD_TYPE_PATTERN      = /(?<build_type>[a-zA-Z0-9\_]{1,100})/
      BUILD_NUMBER_PATTERN    = /(?<build_number>[0-9]{1,100})/

      route(
        /^list$/,
        :list_all,
        command: true,
        help: {
          t('help.list.syntax') => t('help.list.desc')
        }
      )

      route(
        /^list\s#{BUILD_ID_PATTERN}\*$/,
        :list_wild,
        command: true,
        help: {
          t('help.list.syntax_wild') => t('help.list.desc_wild')
        }
      )

      route(
        /^build\s#{BUILD_ID_PATTERN}$/,
        :build,
        command: true,
        help: {
          t('help.build.syntax') => t('help.build.desc')
        }
      )

      route(
        /^build\s#{PR_PATTERN}\sfor\s#{BUILD_ID_PATTERN}$/,
        :buildpr,
        command: true,
        help: {
          t('help.build.prsyntax') => t('help.build.prdesc')
        }
      )

      route(
        /^build\s#{BUILD_ID_PATTERN}\s#{BRANCH_PATTERN}$/,
        :build_branch,
        command: true,
        help: {
          t('help.build.brsyntax') => t('help.build.brdesc')
        }
      )

      route(
        /^build\s#{REVISION_PATTERN}\sfor\s#{BUILD_ID_PATTERN}$/,
        :build_revision,
        command: true,
        help: {
          t('help.build.rsyntax') => t('help.build.rdesc')
        }
      )

      route(
        /^build\s#{REVISION_PATTERN}\sfor\s#{BUILD_ID_PATTERN}\s#{BRANCH_PATTERN}$/,
        :build_branch_revision,
        command: true,
        help: {
          t('help.build.brrsyntax') => t('help.build.brrdesc')
        }
      )

      route(
        /^cp_commits\s+#{REPO_PATTERN}/,
        :list_cps_to_commit,
        command: true,
        help: {
          t('help.cp_commits.syntax') => t('help.cp_commits.desc')
        }
      )

      route(
        /^running$/,
        :running_all,
        command: true,
        help: {
          t('help.running.syntax') => t('help.running.desc')
        }
      )

      route(
        /^running\s#{BUILD_ID_PATTERN}\*$/,
        :running_wild,
        command: true,
        help: {
          t('help.running.syntax_wild') => t('help.running.desc_wild')
        }
      )

      route(
        /^queue$/,
        :queue_all,
        command: true,
        help: {
          t('help.queue.syntax') => t('help.queue.desc')
        }
      )

      route(
        /^queue\s#{BUILD_ID_PATTERN}\*$/,
        :queue_wild,
        command: true,
        help: {
          t('help.queue.syntax_wild') => t('help.queue.desc_wild')
        }
      )

      route(
        /^artifacts\s#{BUILD_TYPE_PATTERN}$/,
        :artifacts_latest,
        command: true,
        help: {
          t('help.artifacts.syntax') => t('help.artifacts.desc')
        }
      )

      route(
        /^artifacts\s#{BUILD_TYPE_PATTERN}\s#{BUILD_NUMBER_PATTERN}$/,
        :artifacts_specific,
        command: true,
        help: {
          t('help.artifacts.syntax_specific') => t('help.artifacts.desc_specific')
        }
      )
 
      def list_cps_to_commit(response)
        repo = response.match_data['repo']
        repo_uri = "#{config.git_uri}/#{repo}.git"
        log.info "repo_uri : #{repo_uri}"

        repos_dir = File.join(Dir.home, 'repos')
        Dir.mkdir(repos_dir) unless File.exists? File.expand_path("#{repos_dir}")

        if File.exists? File.expand_path("#{repos_dir}/#{repo}")
          response.reply(t('git.fetching'))
          log.info "command  : cd #{repos_dir}/#{repo}/ && git fetch -p"
          result = `cd #{repos_dir}/#{repo}/ && git fetch -p`
        else
          response.reply(t('git.cloning'))
          log.info "command  : cd #{repos_dir}/ && git clone #{repo_uri} #{repo}"
          result = `cd #{repos_dir}/ && git clone #{repo_uri} #{repo}`
        end

        result = `cd #{repos_dir}/#{repo}/ && #{config.python_script}`
        response.reply("*Commits to be cherry picked:* ```#{result}```")
      end

      def list_all(response)
        list(response, false)
      end

      def list_wild(response)
        list(response, true)
      end

      def list(response, wildcard)
        begin
          if wildcard
            build_types = fetch_build_types(response.match_data['build_id'])
          else
            build_types = fetch_build_types(nil)
          end
        rescue
          log.error('TeamCity HTTPError')
          response.reply(t('error.request'))
          return
        end

        return response.reply(t('buildtypes.empty')) unless build_types.size > 0

        response.reply(t('buildtypes.list', build_types: build_types))
      end

      def build(response)
        build_id = response.match_data['build_id']
        xml = build_master_xml(build_id)

        log.info "#{xml}"

        build_url = curl_build(xml)
        response.reply("Build has been triggered: #{build_url}")
      end

      def buildpr(response)
        build_id = response.match_data['build_id']
        pr_number = response.match_data['pr'].gsub('pr', '')
        xml = build_pr_xml(build_id, pr_number)

        build_url = curl_build(xml)
        response.reply("Build has been triggered: #{build_url}")
      end

      def build_revision(response)
        build_id = response.match_data['build_id']
        revision = response.match_data['revision'].gsub('r', '')
        xml = build_master_revision_xml(build_id, revision)

        log.info "#{xml}"

        build_url = curl_build(xml)
        response.reply("Build has been triggered: #{build_url}")
      end

      def build_branch(response)
        build_id = response.match_data['build_id']
        branch = response.match_data['branch']
        xml = build_branch_xml(build_id, branch)

        log.info "#{xml}"

        build_url = curl_build(xml)
        response.reply("Build has been triggered: #{build_url}")
      end

      def build_branch_revision(response)
        build_id = response.match_data['build_id']
        branch = response.match_data['branch']
        revision = response.match_data['revision'].gsub('r', '')
        xml = build_branch_revision_xml(build_id, branch, revision)

        log.info "#{xml}"

        build_url = curl_build(xml)
        response.reply("Build has been triggered: #{build_url}")
      end

      def running_all(response)
        running(response, false)
      end

      def running_wild(response)
        running(response, true)
      end

      def running(response, wildcard)
        begin
          if wildcard
            build_types = fetch_running_build(response.match_data['build_id'])
          else
            build_types = fetch_running_build(nil)
          end
        rescue => ex
          log.error('TeamCity HTTPError')
          response.reply(t('error.request'))
          return
        end

        return response.reply(t('runningbuildtypes.empty')) unless build_types.size > 0

        response.reply(t('runningbuildtypes.list', runningbuildtypes: build_types))
      end

      def queue_all(response)
        queue(response, false)
      end

      def queue_wild(response)
        queue(response, true)
      end

      def queue(response, wildcard)
        begin
          if wildcard
            build_types = fetch_queue_build(response.match_data['build_id'])
          else
            build_types = fetch_queue_build(nil)
          end
        rescue => ex
          log.error('TeamCity HTTPError')
          response.reply(t('error.request'))
          return
        end

        return response.reply(t('runningbuildtypes.empty')) unless build_types.size > 0

        response.reply(t('runningbuildtypes.list', runningbuildtypes: build_types))
      end

      def artifacts_latest(response)
        artifacts(response, false)
      end

      def artifacts_specific(response)
        artifacts(response, true)
      end

      def artifacts(response, have_build_number)
        detail = ""
        build_type = response.match_data['build_type']
        build_id = ""
        real_build_number = ""
        if !have_build_number
          build_id, real_build_number = id_build(build_type)
        else
          build_number = response.match_data['build_number']
          build_id, real_build_number = id_build(build_type, build_number)
        end
        return response.reply(t('artifacts.error', 
          buildtype:build_type, buildnumber: real_build_number)) unless build_id != ""

        detail = artifacts_by_build_id(build_type, build_id)

        if detail.empty?
          response.reply(t('artifacts.empty', buildnumber: build_number))
        else 
          response.reply(t('artifacts.list', 
                            build: format_artifacts_build(build_type, build_id, real_build_number), 
                            artifacts: detail))
        end
      end

      #########################################
      ############## HELPERS ##################
      #########################################

      def build_master_xml(build_id)
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.build do |b|
          b.buildType(:id=>"#{build_id}")
          b.properties do |p|
            p.property(:name=>"env.SVN_BRANCH", :value=>"trunk")
            p.property(:name=>"env.SVN_REVISION", :value=>"HEAD")
          end
          b.comment do |c|
            c.text 'Triggering build from TeamCity Slack buildbot.'
          end
        end
      end

      def build_pr_xml(build_id, pr_number)
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.build(:branchName=>"#{pr_number}/merge") do |b|
          b.buildType(:id=>"#{build_id}")
          b.comment do |c|
            c.text 'Triggering build from TeamCity Slack buildbot.'
          end
        end
      end

      def build_master_revision_xml(build_id, revision)
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.build do |b|
          b.buildType(:id=>"#{build_id}")
          b.properties do |p|
            p.property(:name=>"env.SVN_BRANCH", :value=>"trunk")
            p.property(:name=>"env.SVN_REVISION", :value=>"#{revision}")
          end
          b.comment do |c|
            c.text 'Triggering build from TeamCity Slack buildbot.'
          end
        end
      end

      def build_branch_xml(build_id, branch)
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.build do |b|
          b.buildType(:id=>"#{build_id}")
          b.properties do |p|
            p.property(:name=>"env.SVN_BRANCH", :value=>"branches/#{branch}")
            p.property(:name=>"env.SVN_REVISION", :value=>"HEAD")
          end
          b.comment do |c|
            c.text 'Triggering build from TeamCity Slack buildbot.'
          end
        end
      end

      def build_branch_revision_xml(build_id, branch, revision)
        xml = Builder::XmlMarkup.new( :indent => 2 )
        xml.build do |b|
          b.buildType(:id=>"#{build_id}")
          b.properties do |p|
            p.property(:name=>"env.SVN_BRANCH", :value=>"branches/#{branch}")
            p.property(:name=>"env.SVN_REVISION", :value=>"#{revision}")
          end
          b.comment do |c|
            c.text 'Triggering build from TeamCity Slack buildbot.'
          end
        end
      end

      def curl_build(xml)
        path = "#{config.site}/app/rest/buildQueue"
        data = client.post(path, "xml", xml)
        doc = Nokogiri::XML(data)
        build_url = doc.at_xpath('//build/@webUrl').text
        return build_url
      end

      def fetch_build_types(build_id_wildcard)
        response_str = ''
        path = "#{config.site}/httpAuth/app/rest/buildTypes"
        output_data = client.get(path, "json")
        data = JSON.parse(output_data)
        data['buildType'].each do |build_type|
          if build_id_wildcard
            if build_type['id'].include? build_id_wildcard
              response_str << "\n#{build_type['projectName']} :: id=`#{build_type['id']}`"
            end
          else
            response_str << "\n#{build_type['projectName']} :: id=`#{build_type['id']}`"
          end
        end

        return response_str
      end

      def fetch_running_build(build_id_wildcard)
        response_str = ''
        running_url = "#{config.site}/app/rest/builds?locator=running:true,branch:(default:any)"
        data = fetch_builds(running_url)

        if (data['count'] > 0) && (data['build'].any?)
          data['build'].each do |build|
            if build_id_wildcard
              if build['buildTypeId'].include? build_id_wildcard
                response_str << format_result_running_build(build)
              end
            else
              response_str << format_result_running_build(build)
            end
          end
        end

        return response_str
      end

      def fetch_queue_build(build_id_wildcard)
        response_str = ''
        queue_url = "#{config.site}/app/rest/buildQueue"
        data = fetch_builds(queue_url)

        if (data['count'] > 0) && (data['build'].any?)
          data['build'].each do |build|
            if build_id_wildcard
              if build['buildTypeId'].include? build_id_wildcard
                response_str << format_result_queue_build(build)
              end
            else
              response_str << format_result_queue_build(build)
            end
          end
        end

        return response_str
      end

      def fetch_builds(build_url)
        output_data = client.get(build_url, "json")
        data = JSON.parse(output_data)
        return data
      end

      def link_running_build(build_id, build_type_id)
        return "#{config.site}/viewLog.html?buildId=#{build_id}&buildTypeId=#{build_type_id}"
      end

      def link_queue_build(build_id)
        return "#{config.site}/viewQueued.html?itemId=#{build_id}"
      end

      def format_result_running_build(build)
        result = ""
        if build['branchName']
          branch_text = " - #{build['branchName']}"
        else
          branch_text = ""
        end
        link = link_running_build(build['id'], build['buildTypeId'])
        time_diff, is_overtime = remaining_time(build['id'])
        if is_overtime
          result = "\n<#{link}|#{build['buildTypeId']}> (#{build['number']}) - "\
                   "`#{build['percentageComplete']}\%` complete - Over time: `#{time_diff}`#{branch_text}"
        else
          result = "\n<#{link}|#{build['buildTypeId']}> (#{build['number']}) - "\
                   "`#{build['percentageComplete']}\%` complete - Time left: `#{time_diff}`#{branch_text}"
        end
        return result
      end

      def format_result_queue_build(build)
        if build['branchName']
          branch_text = " - #{build['branchName']}"
        else
          branch_text = ""
        end
        link = link_queue_build(build['id'])
        return "\n<#{link}|#{build['buildTypeId']}>#{branch_text}"
      end

      def format_time(seconds)
        strftime = ""
        if seconds > 3600
          strftime = "%Hh:%Mm:%Ss"
        elsif seconds > 60
          strftime = "%Mm:%Ss"
        else
          strftime = "%Ss"
        end
        return strftime
      end

      def remaining_time(build_id)
        return_time = ""
        is_overtime = false
        build_url = "#{config.site}/app/rest/builds/id:#{build_id}"
        data = fetch_builds(build_url)
        if (data['running-info'])
          totalSeconds = data['running-info']['estimatedTotalSeconds'].to_i
          elapsedSeconds = data['running-info']['elapsedSeconds'].to_i
          time_diff = totalSeconds - elapsedSeconds
          if time_diff < 0
            is_overtime = true
            time_diff = time_diff.abs
          end
          time_format = format_time(time_diff)
          return_time = Time.at(time_diff).utc.strftime(time_format)
        end
        return return_time, is_overtime
      end

      def id_build(build_type, build_number = "")
        id = ""
        number = build_number
        build_type_url = "#{config.site}/app/rest/builds/?locator=buildType:#{build_type},"+
                         "status:SUCCESS,state:finished"
        if build_number != ""
          build_type_url = "#{build_type_url},number:#{build_number}"
        end
        begin
          data = fetch_builds(build_type_url)
        rescue
          return id,number
        end
        if (data['count'] > 0) && (data['build'].any?)
          id = data['build'][0]["id"]
          number = data['build'][0]["number"]
        end
        return id,number
      end

      def artifacts_by_build_id(build_type, build_id)
        result = ""
        artifacts_url = "#{config.site}/app/rest/builds/id:#{build_id}/artifacts"
        data = fetch_builds(artifacts_url)
        if (data['count'] > 0) && (data['file'].any?)
          data['file'].each do |file|
            artifact_name = file['name']
            if artifact_name != ""
              result = "#{result}\n#{format_artifact(artifact_name, build_type, build_id)}"
            end
          end
        end
        return result
      end

      def format_artifact(artifact_name, build_type, build_id)
        artifact_url = "#{config.site}/repository/download/#{build_type}/#{build_id}:id"+
                       "/#{artifact_name}"
        return "<#{artifact_url}|#{artifact_name}>"
      end

      def format_artifacts_build(build_type, build_id, build_number)
        artifacts_build_url = "#{link_running_build(build_id, build_type)}&tab=artifacts"
        return "<#{artifacts_build_url}|#{build_type} (#{build_number})>"
      end

      def is_numeric(number)
        true if Integer(number) rescue false
      end
    end

    Lita.register_handler(Teamcity)
  end
end
