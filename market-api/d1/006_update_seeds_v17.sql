-- Update seeds to V17 configuration
-- Generated at: 2026-04-23T09:54:29Z

DELETE FROM providers WHERE id='com.meshnetprotocol.profile';

INSERT INTO providers (
  id,
  name,
  description,
  tags_json,
  author,
  updated_at,
  price_per_gb_usd,
  visibility,
  status,
  config_json,
  routing_rules_json
) VALUES (
  'com.meshnetprotocol.profile',
  '官方极速节点 (SmartRouting)',
  'V17版本的种子，包含动态标签测试',
  '["Seeds","SmartRouting","V13"]',
  'OpenMesh Team',
  '1970-01-01T00:00:00Z',
  0.0,
  'public',
  'active',
  '{"log":{"level":"debug"},"dns":{"servers":[{"tag":"local-dns","address":"223.5.5.5","detour":"direct"},{"tag":"google-dns","address":"https://dns.google/dns-query","detour":"primary-selector"}],"rules":[{"rule_set":"geosite-geolocation-cn","server":"local-dns"}],"final":"google-dns","strategy":"ipv4_only"},"inbounds":[{"type":"tun","tag":"tun-in","address":["198.18.0.1/15","fdfe:dcba::1/126"],"auto_route":true,"strict_route":false,"route_exclude_address":["127.0.0.0/8","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16","169.254.0.0/16","223.5.5.5/32","::1/128","fc00::/7","fe80::/10"],"route_exclude_address_set":["geoip-cn"],"sniff":true,"sniff_override_destination":true}],"outbounds":[{"type":"shadowsocks","tag":"meshflux150 [加拿大]","server":"216.128.182.150","server_port":14370,"method":"aes-256-gcm","password":"uqaflxM4EiDaCfDV"},{"type":"shadowsocks","tag":"meshflux150 [韩国]","server":"158.247.225.150","server_port":14036,"method":"aes-256-gcm","password":"jQAngGDKdSA8twbQ"},{"type":"shadowsocks","tag":"meshflux66 [以色列]","server":"64.177.64.66","server_port":12370,"method":"aes-256-gcm","password":"9szb3jq8CBTxgrWg"},{"type":"selector","tag":"primary-selector","outbounds":["meshflux150 [加拿大]","meshflux66 [以色列]","meshflux150 [韩国]"],"default":"meshflux150 [加拿大]"},{"type":"direct","tag":"direct"}],"route":{"rules":[{"action":"sniff"},{"protocol":"dns","action":"hijack-dns"},{"domain_suffix":["google.com","googleapis.com","gstatic.com","googleusercontent.com","gvt1.com","gvt2.com","1e100.net","youtube.com","ytimg.com","ggpht.com","android.com","app-measurement.com","github.com","githubusercontent.com","twitter.com","telegram.org","claude.ai","openai.com","facebook.com","fbcdn.net","instagram.com","whatsapp.com","whatsapp.net","tiktok.com","byteoversea.com","netflix.com","bing.com","perplexity.ai","deepl.com"],"outbound":"primary-selector"},{"rule_set":"geosite-geolocation-cn","outbound":"direct"},{"rule_set":"geoip-cn","outbound":"direct"},{"domain_suffix":["localhost","local"],"outbound":"direct"},{"ip_is_private":true,"outbound":"direct"}],"final":"primary-selector","auto_detect_interface":true,"rule_set":[{"type":"remote","tag":"geoip-cn","format":"binary","url":"https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs","download_detour":"primary-selector","update_interval":"1d"},{"type":"remote","tag":"geosite-geolocation-cn","format":"binary","url":"https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs","download_detour":"primary-selector","update_interval":"1d"}]}}',
  '{"version":2,"proxy":{"domain":[],"domain_suffix":[]}}'
);
