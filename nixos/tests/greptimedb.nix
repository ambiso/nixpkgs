{ pkgs, ... }:
{
  name = "greptimedb";

  nodes.machine =
    { ... }:
    {
      services.greptimedb = {
        enable = true;
        settings = {
          enable_telemetry = false;
          http.addr = "127.0.0.1:14000";
          grpc.bind_addr = "127.0.0.1:14001";
          mysql.enable = false;
          postgres = {
            enable = true;
            addr = "127.0.0.1:14003";
          };
          logging = {
            dir = "";
            append_stdout = true;
          };
        };
      };

      environment.systemPackages = [ pkgs.curl ];
    };

  testScript = ''
    start_all()

    machine.wait_for_unit("greptimedb.service")
    machine.wait_for_open_port(14000)
    machine.wait_for_open_port(14003)

    machine.succeed(
        "curl --fail --silent --data-urlencode "
        "'sql=CREATE TABLE readings (host STRING NOT NULL, ts TIMESTAMP(3) NOT NULL TIME INDEX, sensor_value DOUBLE, PRIMARY KEY (host))' "
        "http://127.0.0.1:14000/v1/sql?db=public"
    )
    machine.succeed(
        "curl --fail --silent --data-urlencode "
        "\"sql=INSERT INTO readings VALUES ('test', 0, 42.5)\" "
        "http://127.0.0.1:14000/v1/sql?db=public"
    )

    machine.systemctl("restart greptimedb.service")
    machine.wait_for_open_port(14000)
    result = machine.succeed(
        "curl --fail --silent --data-urlencode "
        "'sql=SELECT host, sensor_value FROM readings' "
        "http://127.0.0.1:14000/v1/sql?db=public"
    )
    assert '"test"' in result
    assert "42.5" in result
  '';
}
