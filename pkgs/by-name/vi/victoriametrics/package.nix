{
  lib,
  buildGoModule,
  fetchFromGitHub,
  nixosTests,
  withServer ? true, # the actual metrics server
  withVmAgent ? true, # Agent to collect metrics
  withVmAlert ? true, # Alert Manager
  withVmAuth ? true, # HTTP proxy for authentication
  withBackupTools ? true, # vmbackup, vmrestore
  withVmctl ? true, # vmctl is used to migrate time series
}:

buildGoModule (finalAttrs: {
  pname = "VictoriaMetrics";
  version = "1.122.0";

  src = fetchFromGitHub {
    owner = "VictoriaMetrics";
    repo = "VictoriaMetrics";
    tag = "v${finalAttrs.version}";
    hash = "sha256-CpxnCW4+hsc3SQZXMI0pkPnKPvh1GTvCmhg5NkSZbk4=";
  };

  vendorHash = null;

  subPackages =
    lib.optionals withServer [
      "app/victoria-metrics"
      "app/vminsert"
      "app/vmselect"
      "app/vmstorage"
      "app/vmui"
    ]
    ++ lib.optionals withVmAgent [ "app/vmagent" ]
    ++ lib.optionals withVmAlert [
      "app/vmalert"
      "app/vmalert-tool"
    ]
    ++ lib.optionals withVmAuth [ "app/vmauth" ]
    ++ lib.optionals withVmctl [ "app/vmctl" ]
    ++ lib.optionals withBackupTools [
      "app/vmbackup"
      "app/vmrestore"
    ];

  postPatch = ''
    # main module (github.com/VictoriaMetrics/VictoriaMetrics) does not contain package
    # github.com/VictoriaMetrics/VictoriaMetrics/app/vmui/packages/vmui/web
    #
    # This appears to be some kind of test server for development purposes only.
    rm -f app/vmui/packages/vmui/web/{go.mod,main.go}

    # Increase timeouts in tests to prevent failure on heavily loaded builders
    substituteInPlace lib/storage/storage_test.go \
      --replace-fail "time.After(10 " "time.After(120 " \
      --replace-fail "time.NewTimer(30 " "time.NewTimer(120 " \
      --replace-fail "time.NewTimer(time.Second * 10)" "time.NewTimer(time.Second * 120)" \
  '';

  ldflags = [
    "-s"
    "-w"
    "-X github.com/VictoriaMetrics/VictoriaMetrics/lib/buildinfo.Version=${finalAttrs.version}"
  ];

  preCheck = ''
    # `lib/querytracer/tracer_test.go` expects `buildinfo.Version` to be unset
    export ldflags=''${ldflags//=${finalAttrs.version}/=}
  '';

  __darwinAllowLocalNetworking = true;

  passthru = {
    tests = {
      inherit (nixosTests) victoriametrics;
    };
    updateScript = ./update.sh;
  };

  meta = {
    homepage = "https://victoriametrics.com/";
    description = "Fast, cost-effective and scalable time series database, long-term remote storage for Prometheus";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      yorickvp
      ivan
      leona
      shawn8901
      ryan4yin
    ];
    changelog = "https://github.com/VictoriaMetrics/VictoriaMetrics/releases/tag/v${finalAttrs.version}";
    mainProgram = "victoria-metrics";
  };
})
