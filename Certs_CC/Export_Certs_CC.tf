locals {
  source_certificates_map_cc = {
    "Test" = {
      account_ids = ["031332257227", ]
      regions     = ["us-east-2", ]
      certs = [
        "test.jf30.dedyn.io", # 101
      ]
    }
    //
    "Test1" = {
      account_ids = ["031332257227", ]
      regions     = ["us-west-2", ]
      certs = [
        "test1.jf30.dedyn.io", # 101
      ]
    }
    //
  }
}