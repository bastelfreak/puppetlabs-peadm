# @summary Perform initial installation of Puppet Enterprise Extra Large
#
plan pe_xl::install (
  Boolean             $ha,
  String[1]           $master_host,
  String[1]           $puppetdb_database_host,
  String[1]           $master_replica_host,
  String[1]           $puppetdb_database_replica_host,
  Array[String[1]]    $compiler_hosts = [ ],

  String[1]           $console_password,
  String[1]           $version = '2018.1.3',
  Hash                $r10k_sources = { },
  Array[String[1]]    $dns_alt_names = [ ],

  String[1]           $stagingdir = '/tmp',
) {

  # TODO: remove 'SLV-365' comments

  # Define a number of host groupings for use later in the plan

  # SLV-365 - separate core / ha hosts
  # $all_hosts = [
  #   $master_host,
  #   $puppetdb_database_host,
  #   $compiler_hosts,
  #   $master_replica_host,
  #   $puppetdb_database_replica_host,
  # ].pe_xl::flatten_compact()

  if $ha {
    out::message('Proceeding with Extra Large HA installation...')
  } else {
    out::message('Proceeding with basic Extra Large installation...')
  }

  $core_hosts = [
    $master_host,
    $puppetdb_database_host,
    $compiler_hosts,
  ]

  $ha_hosts = [
    $master_replica_host,
    $puppetdb_database_replica_host,
  ]

  if $ha {
    $all_hosts = [
      $core_hosts,
      $ha_hosts,
    ].pe_xl::flatten_compact()
  } else {
    $all_hosts = [
      $core_hosts,
    ].pe_xl::flatten_compact()
  }

  out::message("all_hosts: ${all_hosts}")

  # SLV-365
  # $pe_installer_hosts = [
  #   $master_host,
  #   $puppetdb_database_host,
  #   $master_replica_host,
  # ].pe_xl::flatten_compact()

  if $ha {
    $pe_installer_hosts = [
      $master_host,
      $puppetdb_database_host,
      $master_replica_host,
    ].pe_xl::flatten_compact()
  } else {
    $pe_installer_hosts = [
      $master_host,
      $puppetdb_database_host,
    ].pe_xl::flatten_compact()
  }

  # SLV-365 -
  # $agent_installer_hosts = [
  #   $compiler_hosts,
  #   $master_replica_host,
  # ].pe_xl::flatten_compact()

  if $ha {
    $agent_installer_hosts = [
      $compiler_hosts,
      $master_replica_host,
    ].pe_xl::flatten_compact()
  } else {
    $agent_installer_hosts = [
      $compiler_hosts,
    ].pe_xl::flatten_compact()
  }

  # There is currently a problem with OID names in csr_attributes.yaml for some
  # installs. Use the raw OIDs for now.
  $pp_application = '1.3.6.1.4.1.34380.1.1.8'
  $pp_cluster     = '1.3.6.1.4.1.34380.1.1.16'
  $pp_role        = '1.3.6.1.4.1.34380.1.1.13'

  # Clusters A and B are used to divide PuppetDB availability for compilers

  # SLV-365
  # $cm_cluster_a = $compiler_hosts.filter |$index,$cm| { $index % 2 == 0 }
  # $cm_cluster_b = $compiler_hosts.filter |$index,$cm| { $index % 2 != 0 }

  if $ha {
    $cm_cluster_a = $compiler_hosts.filter |$index,$cm| { $index % 2 == 0 }
    $cm_cluster_b = $compiler_hosts.filter |$index,$cm| { $index % 2 != 0 }
  }

  $dns_alt_names_csv = $dns_alt_names.reduce |$csv,$x| { "${csv},${x}" }

  # Validate that the name given for each system is both a resolvable name AND
  # the configured hostname.
  run_task('pe_xl::hostname', $all_hosts).each |$result| {
    if $result.target.name != $result['hostname'] {
      fail_plan("Hostname / DNS name mismatch: target ${result.target.name} reports '${result['hostname']}'")
    }
  }

  # Generate all the needed pe.conf files
  $master_pe_conf = epp('pe_xl/master-pe.conf.epp',
    console_password       => $console_password,
    master_host            => $master_host,
    puppetdb_database_host => $puppetdb_database_host,
    dns_alt_names          => $dns_alt_names,
    r10k_sources           => $r10k_sources,
  )

  $puppetdb_database_pe_conf = epp('pe_xl/puppetdb_database-pe.conf.epp',
    master_host            => $master_host,
    puppetdb_database_host => $puppetdb_database_host,
  )

  # SLV-365
  # $puppetdb_database_replica_pe_conf = epp('pe_xl/puppetdb_database-pe.conf.epp',
  #   master_host            => $master_host,
  #   puppetdb_database_host => $puppetdb_database_replica_host,
  # )

  if $ha {
    $puppetdb_database_replica_pe_conf = epp('pe_xl/puppetdb_database-pe.conf.epp',
      master_host            => $master_host,
      puppetdb_database_host => $puppetdb_database_replica_host,
    )
  }

  # Upload the pe.conf files to the hosts that need them
  pe_xl::file_content_upload($master_pe_conf, '/tmp/pe.conf', $master_host)
  pe_xl::file_content_upload($puppetdb_database_pe_conf, '/tmp/pe.conf', $puppetdb_database_host)

  # SLV-365
  # pe_xl::file_content_upload($puppetdb_database_replica_pe_conf, '/tmp/pe.conf', $puppetdb_database_replica_host)

  if $ha {
    pe_xl::file_content_upload($puppetdb_database_replica_pe_conf, '/tmp/pe.conf', $puppetdb_database_replica_host)
  }

  # Download the PE tarball and send it to the nodes that need it
  $pe_tarball_name     = "puppet-enterprise-${version}-el-7-x86_64.tar.gz"
  $local_tarball_path  = "${stagingdir}/${pe_tarball_name}"
  $upload_tarball_path = "/tmp/${pe_tarball_name}"

  # SLV-365
  # run_plan('pe_xl::util::retrieve_and_upload',
  #   nodes       => [$master_host, $puppetdb_database_host, $puppetdb_database_replica_host],
  #   source      => "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
  #   local_path  => $local_tarball_path,
  #   upload_path => $upload_tarball_path,
  # )

  if $ha {
    $retrieve_and_upload_hosts = [$master_host, $puppetdb_database_host, $puppetdb_database_replica_host]
  } else {
    $retrieve_and_upload_hosts = [$master_host, $puppetdb_database_host]
  }

  run_plan('pe_xl::util::retrieve_and_upload',
    nodes       => $retrieve_and_upload_hosts,
    source      => "https://s3.amazonaws.com/pe-builds/released/${version}/puppet-enterprise-${version}-el-7-x86_64.tar.gz",
    local_path  => $local_tarball_path,
    upload_path => $upload_tarball_path,
  )

  # Create csr_attributes.yaml files for the nodes that need them
  run_task('pe_xl::mkdir_p_file', $master_host,
    path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    content => @("HEREDOC"),
      ---
      extension_requests:
        ${pp_application}: "puppet"
        ${pp_role}: "pe_xl::master"
        ${pp_cluster}: "A"
      | HEREDOC
  )

  run_task('pe_xl::mkdir_p_file', $puppetdb_database_host,
    path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
    content => @("HEREDOC"),
      ---
      extension_requests:
        ${pp_application}: "puppet"
        ${pp_role}: "pe_xl::puppetdb_database"
        ${pp_cluster}: "A"
      | HEREDOC
  )

  # SLV-365
  # run_task('pe_xl::mkdir_p_file', $puppetdb_database_replica_host,
  #   path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
  #   content => @("HEREDOC"),
  #     ---
  #     extension_requests:
  #       ${pp_application}: "puppet"
  #       ${pp_role}: "pe_xl::puppetdb_database"
  #       ${pp_cluster}: "B"
  #     | HEREDOC
  # )

  if $ha {
    run_task('pe_xl::mkdir_p_file', $puppetdb_database_replica_host,
      path    => '/etc/puppetlabs/puppet/csr_attributes.yaml',
      content => @("HEREDOC"),
      ---
      extension_requests:
        ${pp_application}: "puppet"
        ${pp_role}: "pe_xl::puppetdb_database"
        ${pp_cluster}: "B"
      | HEREDOC
    )
  }

  # Get the master installation up and running. The installer will
  # "fail" because PuppetDB can't start. That's expected.
  without_default_logging() || {
    notice("Starting: task pe_xl::pe_install on ${master_host}")
    run_task('pe_xl::pe_install', $master_host,
      _catch_errors         => true,
      tarball               => $upload_tarball_path,
      peconf                => '/tmp/pe.conf',
      shortcircuit_puppetdb => true,
    )
    notice("Finished: task pe_xl::pe_install on ${master_host}")
  }

  # Configure autosigning for the puppetdb database hosts 'cause they need it

  # SLV-365
  # run_task('pe_xl::mkdir_p_file', $master_host,
  #   path    => '/etc/puppetlabs/puppet/autosign.conf',
  #   owner   => 'pe-puppet',
  #   group   => 'pe-puppet',
  #   mode    => '0644',
  #   content => @("HEREDOC"),
  #     ${puppetdb_database_host}
  #     ${puppetdb_database_replica_host}
  #     | HEREDOC
  # )

  # TODO: resolve syntax error in this approach
  # if $ha {
  #   $content = @("HEREDOC"),
  #       ${puppetdb_database_host}
  #       ${puppetdb_database_replica_host}
  #       | HEREDOC
  # } else {
  #   $content = @("HEREDOC"),
  #       ${puppetdb_database_host}
  #       | HEREDOC
  # }

  # run_task('pe_xl::mkdir_p_file', $master_host,
  #   path    => '/etc/puppetlabs/puppet/autosign.conf',
  #   owner   => 'pe-puppet',
  #   group   => 'pe-puppet',
  #   mode    => '0644',
  #   content => $content
  # )

  # TODO: replace with the commented approach above if resolved
  if $ha {
    run_task('pe_xl::mkdir_p_file', $master_host,
      path    => '/etc/puppetlabs/puppet/autosign.conf',
      owner   => 'pe-puppet',
      group   => 'pe-puppet',
      mode    => '0644',
      content => @("HEREDOC"),
        ${puppetdb_database_host}
        ${puppetdb_database_replica_host}
        | HEREDOC
    )
  } else {
    run_task('pe_xl::mkdir_p_file', $master_host,
      path    => '/etc/puppetlabs/puppet/autosign.conf',
      owner   => 'pe-puppet',
      group   => 'pe-puppet',
      mode    => '0644',
      content => @("HEREDOC"),
        ${puppetdb_database_host}
        | HEREDOC
    )
  }

  # Run the PE installer on the puppetdb database hosts

  # SLV-365
  # run_task('pe_xl::pe_install', [$puppetdb_database_host, $puppetdb_database_replica_host],
  #   tarball => $upload_tarball_path,
  #   peconf  => '/tmp/pe.conf',
  # )

  if $ha {
    $database_hosts = [$puppetdb_database_host, $puppetdb_database_replica_host]
  } else {
    $database_hosts = [$puppetdb_database_host]
  }

  run_task('pe_xl::pe_install', $database_hosts,
    tarball => $upload_tarball_path,
    peconf  => '/tmp/pe.conf',
  )

  # Now that the main PuppetDB database node is ready, finish priming the
  # master. Explicitly stop puppetdb first to avoid any systemd interference.
  run_command('systemctl stop pe-puppetdb', $master_host)
  run_command('systemctl start pe-puppetdb', $master_host)
  run_task('pe_xl::rbac_token', $master_host,
    password => $console_password,
  )

  # Stub a production environment and commit it to file-sync. At least one
  # commit (content irrelevant) is necessary to be able to configure
  # replication. A production environment must exist when committed to avoid
  # corrupting the PE console. Create the site.pp file specifically to avoid
  # breaking the `puppet infra configure` command.
  run_task('pe_xl::mkdir_p_file', $master_host,
    path    => '/etc/puppetlabs/code-staging/environments/production/manifests/site.pp',
    chown_r => '/etc/puppetlabs/code-staging/environments',
    owner   => 'pe-puppet',
    group   => 'pe-puppet',
    mode    => '0644',
    content => "# Empty manifest\n",
  )

  run_task('pe_xl::code_manager', $master_host,
    action => 'file-sync commit',
  )

  # Deploy the PE agent to all remaining hosts
  ##############
  # SLV-365 - clusters A & B?
  ##############
  # run_task('pe_xl::agent_install', $master_replica_host,
  #   server        => $master_host,
  #   install_flags => [
  #     '--puppet-service-ensure', 'stopped',
  #     "main:dns_alt_names=${dns_alt_names_csv}",
  #     'extension_requests:pp_application=puppet',
  #     'extension_requests:pp_role=pe_xl::master',
  #     'extension_requests:pp_cluster=B',
  #   ],
  # )
  #
  # run_task('pe_xl::agent_install', $cm_cluster_a,
  #   server        => $master_host,
  #   install_flags => [
  #     '--puppet-service-ensure', 'stopped',
  #     "main:dns_alt_names=${dns_alt_names_csv}",
  #     'extension_requests:pp_application=puppet',
  #     'extension_requests:pp_role=pe_xl::compiler',
  #     'extension_requests:pp_cluster=A',
  #   ],
  # )
  #
  # run_task('pe_xl::agent_install', $cm_cluster_b,
  #   server        => $master_host,
  #   install_flags => [
  #     '--puppet-service-ensure', 'stopped',
  #     "main:dns_alt_names=${dns_alt_names_csv}",
  #     'extension_requests:pp_application=puppet',
  #     'extension_requests:pp_role=pe_xl::compiler',
  #     'extension_requests:pp_cluster=B',
  #   ],
  # )

  if $ha {
    run_task('pe_xl::agent_install', $master_replica_host,
      server        => $master_host,
      install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::master',
      'extension_requests:pp_cluster=B',
      ],
    )

    run_task('pe_xl::agent_install', $cm_cluster_a,
      server        => $master_host,
      install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::compiler',
      'extension_requests:pp_cluster=A',
      ],
    )

    run_task('pe_xl::agent_install', $cm_cluster_b,
      server        => $master_host,
      install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::compiler',
      'extension_requests:pp_cluster=B',
      ],
    )
  } else {
    run_task('pe_xl::agent_install', $compiler_hosts,
      server        => $master_host,
      install_flags => [
      '--puppet-service-ensure', 'stopped',
      "main:dns_alt_names=${dns_alt_names_csv}",
      'extension_requests:pp_application=puppet',
      'extension_requests:pp_role=pe_xl::compiler',
      'extension_requests:pp_cluster=A',
      ],
    )
  }

  # Do a Puppet agent run to ensure certificate requests have been submitted
  # These runs will "fail", and that's expected.
  without_default_logging() || {
    notice("Starting: task pe_xl::puppet_runonce on ${agent_installer_hosts}")
    run_task('pe_xl::puppet_runonce', $agent_installer_hosts, {_catch_errors => true})
    notice("Finished: task pe_xl::puppet_runonce on ${agent_installer_hosts}")
  }

  # Ensure some basic configuration on the master needed at install time.
  if ($version.versioncmp('2019.0') < 0) {
    apply($master_host) { include pe_xl::setup::master }.pe_xl::print_apply_result
  }

  run_command(inline_epp(@(HEREDOC)), $master_host)
    /opt/puppetlabs/bin/puppetserver ca sign --certname <%= $agent_installer_hosts.join(',') -%>
    | HEREDOC

  run_task('pe_xl::puppet_runonce', $master_host)
  run_task('pe_xl::puppet_runonce', $all_hosts - $master_host)

  return('Installation succeeded')
}
