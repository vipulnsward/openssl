# frozen_string_literal: false
require_relative "utils"

if defined?(OpenSSL::TestUtils)

class OpenSSL::TestOCSP < OpenSSL::TestCase
  def setup
    now = Time.at(Time.now.to_i) # suppress usec
    dgst = OpenSSL::Digest::SHA1.new

    # @ca_cert
    #   |
    # @cert
    #   |----------|
    # @cert2   @ocsp_cert

    ca_subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCA")
    @ca_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    ca_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    @ca_cert = OpenSSL::TestUtils.issue_cert(
       ca_subj, @ca_key, 1, now, now+3600, ca_exts, nil, nil, dgst)

    cert_subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCA2")
    @cert_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    cert_exts = [
      ["basicConstraints", "CA:TRUE", true],
      ["keyUsage", "cRLSign,keyCertSign", true],
    ]
    @cert = OpenSSL::TestUtils.issue_cert(
       cert_subj, @cert_key, 5, now, now+3600, cert_exts, @ca_cert, @ca_key, dgst)

    cert2_subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCert")
    @cert2_key = OpenSSL::TestUtils::TEST_KEY_RSA1024
    cert2_exts = [
    ]
    @cert2 = OpenSSL::TestUtils.issue_cert(
       cert2_subj, @cert2_key, 10, now, now+3600, cert2_exts, @cert, @cert_key, dgst)

    ocsp_subj = OpenSSL::X509::Name.parse("/DC=org/DC=ruby-lang/CN=TestCAOCSP")
    @ocsp_key = OpenSSL::TestUtils::TEST_KEY_RSA2048
    ocsp_exts = [
      ["extendedKeyUsage", "OCSPSigning", true],
    ]
    @ocsp_cert = OpenSSL::TestUtils.issue_cert(
       ocsp_subj, @ocsp_key, 100, now, now+3600, ocsp_exts, @cert, @cert_key, "SHA256")
  end

  def test_new_certificate_id
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    assert_kind_of OpenSSL::OCSP::CertificateId, cid
    assert_equal @cert.serial, cid.serial
  end

  def test_certificate_id_issuer_name_hash
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_equal OpenSSL::Digest::SHA1.hexdigest(@cert.issuer.to_der), cid.issuer_name_hash
    assert_equal "d91f736ac4dc3242f0fb9b77a3149bd83c5c43d0", cid.issuer_name_hash
  end

  def test_certificate_id_issuer_key_hash
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_equal OpenSSL::Digest::SHA1.hexdigest(OpenSSL::ASN1.decode(@ca_cert.to_der).value[0].value[6].value[1].value), cid.issuer_key_hash
    assert_equal "d1fef9fbf8ae1bc160cbfa03e2596dd873089213", cid.issuer_key_hash
  end

  def test_certificate_id_hash_algorithm
    cid_sha1 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    cid_sha256 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    assert_equal "sha1", cid_sha1.hash_algorithm
    assert_equal "sha256", cid_sha256.hash_algorithm
  end

  def test_certificate_id_der
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert) # hash algorithm defaults to SHA-1
    der = cid.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal OpenSSL::ASN1.ObjectId("SHA1").to_der, asn1.value[0].value[0].to_der
    assert_equal OpenSSL::Digest::SHA1.digest(@cert.issuer.to_der), asn1.value[1].value
    assert_equal OpenSSL::Digest::SHA1.digest(OpenSSL::ASN1.decode(@ca_cert.to_der).value[0].value[6].value[1].value), asn1.value[2].value
    assert_equal @cert.serial, asn1.value[3].value
    assert_equal der, OpenSSL::OCSP::CertificateId.new(der).to_der
  end

  def test_certificate_id_dup
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    assert_equal cid.to_der, cid.dup.to_der
  end

  def test_request_der
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    request.sign(@cert, @cert_key, [@ca_cert], 0)
    asn1 = OpenSSL::ASN1.decode(request.to_der)
    assert_equal cid.to_der, asn1.value[0].value.find { |a| a.tag_class == :UNIVERSAL }.value[0].value[0].to_der
    assert_equal OpenSSL::ASN1.ObjectId("sha1WithRSAEncryption").to_der, asn1.value[1].value[0].value[0].value[0].to_der
    assert_equal @cert.to_der, asn1.value[1].value[0].value[2].value[0].value[0].to_der
    assert_equal @ca_cert.to_der, asn1.value[1].value[0].value[2].value[0].value[1].to_der
    assert_equal asn1.to_der, OpenSSL::OCSP::Request.new(asn1.to_der).to_der
  end

  def test_request_sign_verify
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    request.sign(@cert, @cert_key, nil, 0, "SHA1")
    assert_equal cid.to_der, request.certid.first.to_der
    store1 = OpenSSL::X509::Store.new; store1.add_cert(@ca_cert)
    assert_equal true, request.verify([@cert], store1)
    assert_equal true, request.verify([], store1)
    store2 = OpenSSL::X509::Store.new; store1.add_cert(@cert)
    assert_equal false, request.verify([], store2)
    assert_equal true, request.verify([], store2, OpenSSL::OCSP::NOVERIFY)
  end

  def test_request_nonce
    req0 = OpenSSL::OCSP::Request.new
    req1 = OpenSSL::OCSP::Request.new
    req1.add_nonce("NONCE")
    req2 = OpenSSL::OCSP::Request.new
    req2.add_nonce("NONCF")
    bres = OpenSSL::OCSP::BasicResponse.new
    assert_equal 2, req0.check_nonce(bres)
    bres.copy_nonce(req1)
    assert_equal 1, req1.check_nonce(bres)
    bres.add_nonce("NONCE")
    assert_equal 1, req1.check_nonce(bres)
    assert_equal 0, req2.check_nonce(bres)
    assert_equal 3, req0.check_nonce(bres)
  end

  def test_request_dup
    request = OpenSSL::OCSP::Request.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    request.add_certid(cid)
    assert_equal request.to_der, request.dup.to_der
  end

  def test_basic_response_der
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, 0, nil, -300, 500, [])
    bres.add_nonce("NONCE")
    bres.sign(@ocsp_cert, @ocsp_key, [@ca_cert], 0)
    der = bres.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal cid.to_der, asn1.value[0].value.find { |a| a.class == OpenSSL::ASN1::Sequence }.value[0].value[0].to_der
    assert_equal OpenSSL::ASN1.Sequence([@ocsp_cert, @ca_cert]).to_der, asn1.value[3].value[0].to_der
    assert_equal der, OpenSSL::OCSP::BasicResponse.new(der).to_der
  rescue TypeError
    if /GENERALIZEDTIME/ =~ $!.message
      pend "OCSP_basic_sign() is broken"
    else
      raise
    end
  end

  def test_basic_response_sign_verify_signed_by_root_ca
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA256.new)
    bres = OpenSSL::OCSP::BasicResponse.new
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, -400, -300, 500, [])
    bres.sign(@ca_cert, @ca_key, nil, 0, "SHA256") # BasicResponse doesn't contain @ca_cert
    store1 = OpenSSL::X509::Store.new; store1.add_cert(@ca_cert)
    assert_equal false, bres.verify([], store1)
    assert_equal true, bres.verify([@ca_cert], store1)
    store2 = OpenSSL::X509::Store.new
    assert_equal false, bres.verify([@ca_cert], store2)
    assert_equal true, bres.verify([@ca_cert], store2, OpenSSL::OCSP::TRUSTOTHER)
  end

  def test_basic_response_sign_verify_signed_by_ocsp_signer
    cid = OpenSSL::OCSP::CertificateId.new(@cert2, @cert)
    bres = OpenSSL::OCSP::BasicResponse.new
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, -400, -300, 500, [])
    bres.sign(@ocsp_cert, @ocsp_key, [@cert]) # BasicResponse contains @ocsp_cert
    store1 = OpenSSL::X509::Store.new; store1.add_cert(@ca_cert)
    assert_equal true, bres.verify([], store1)
    assert_equal false, bres.verify([], store1, OpenSSL::OCSP::NOCHAIN)
  end

  def test_basic_response_sign_verify_use_extra_chain
    # OpenSSL had a bug on this; test that our workaround works
    cid = OpenSSL::OCSP::CertificateId.new(@cert2, @cert, OpenSSL::Digest::SHA256.new)
    bres = OpenSSL::OCSP::BasicResponse.new
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, -400, -300, 500, [])
    bres.sign(@ocsp_cert, @ocsp_key, [], 0, "SHA256")
    store1 = OpenSSL::X509::Store.new; store1.add_cert(@ca_cert)
    assert_equal true, bres.verify([@cert], store1)
    assert_equal false, bres.verify([], store1, OpenSSL::OCSP::NOCHAIN)
  end

  def test_basic_response_dup
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, 0, nil, -300, 500, [])
    bres.sign(@ocsp_cert, @ocsp_key, [@ca_cert], 0)
    assert_equal bres.to_der, bres.dup.to_der
  end

  def test_basic_response_response_operations
    bres = OpenSSL::OCSP::BasicResponse.new
    now = Time.at(Time.now.to_i)
    cid1 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    cid2 = OpenSSL::OCSP::CertificateId.new(@ocsp_cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    cid3 = OpenSSL::OCSP::CertificateId.new(@ca_cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid1, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, now - 400, -300, nil, nil)
    bres.add_status(cid2, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, nil, -300, 500, [])

    assert_equal 2, bres.responses.size
    single = bres.responses.first
    assert_equal cid1.to_der, single.certid.to_der
    assert_equal OpenSSL::OCSP::V_CERTSTATUS_REVOKED, single.cert_status
    assert_equal OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, single.revocation_reason
    assert_equal now - 400, single.revocation_time
    assert_in_delta (now - 301), single.this_update, 1
    assert_equal nil, single.next_update
    assert_equal [], single.extensions

    assert_equal cid2.to_der, bres.find_response(cid2).certid.to_der
    assert_equal nil, bres.find_response(cid3)
  end

  def test_single_response_der
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, nil, -300, 500, nil)
    single = bres.responses[0]
    der = single.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal :CONTEXT_SPECIFIC, asn1.value[1].tag_class
    assert_equal 0, asn1.value[1].tag # good
    assert_equal der, OpenSSL::OCSP::SingleResponse.new(der).to_der
  end

  def test_single_response_check_validity
    bres = OpenSSL::OCSP::BasicResponse.new
    cid1 = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    cid2 = OpenSSL::OCSP::CertificateId.new(@ocsp_cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid1, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, -400, -300, -50, [])
    bres.add_status(cid2, OpenSSL::OCSP::V_CERTSTATUS_REVOKED, OpenSSL::OCSP::REVOKED_STATUS_UNSPECIFIED, -400, -300, nil, [])
    bres.add_status(cid2, OpenSSL::OCSP::V_CERTSTATUS_GOOD, nil, nil, Time.now + 100, nil, nil)

    if bres.responses[2].check_validity # thisUpdate is in future; must fail
      # LibreSSL bug; skip for now
      pend "OCSP_check_validity() is broken"
    end

    single1 = bres.responses[0]
    assert_equal false, single1.check_validity
    assert_equal false, single1.check_validity(30)
    assert_equal true, single1.check_validity(60)
    single2 = bres.responses[1]
    assert_equal true, single2.check_validity
    assert_equal true, single2.check_validity(0, 500)
    assert_equal false, single2.check_validity(0, 200)
  end

  def test_response_der
    bres = OpenSSL::OCSP::BasicResponse.new
    cid = OpenSSL::OCSP::CertificateId.new(@cert, @ca_cert, OpenSSL::Digest::SHA1.new)
    bres.add_status(cid, OpenSSL::OCSP::V_CERTSTATUS_GOOD, 0, nil, -300, 500, [])
    bres.sign(@ocsp_cert, @ocsp_key, [@ca_cert], 0)
    res = OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, bres)
    der = res.to_der
    asn1 = OpenSSL::ASN1.decode(der)
    assert_equal OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, asn1.value[0].value
    assert_equal OpenSSL::ASN1.ObjectId("basicOCSPResponse").to_der, asn1.value[1].value[0].value[0].to_der
    assert_equal bres.to_der, asn1.value[1].value[0].value[1].value
    assert_equal der, OpenSSL::OCSP::Response.new(der).to_der
  end

  def test_response_dup
    bres = OpenSSL::OCSP::BasicResponse.new
    bres.sign(@ocsp_cert, @ocsp_key, [@ca_cert], 0)
    res = OpenSSL::OCSP::Response.create(OpenSSL::OCSP::RESPONSE_STATUS_SUCCESSFUL, bres)
    assert_equal res.to_der, res.dup.to_der
  end
end

end
