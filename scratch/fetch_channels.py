import urllib.request
import urllib.parse
import xml.dom.minidom

url = "http://mdy4-server.netbird.cloud:81/ISAPI/Streaming/channels"
username = "admin"
password = "m$DVRpwd"

password_mgr = urllib.request.HTTPPasswordMgrWithDefaultRealm()
password_mgr.add_password(None, url, username, password)
handler = urllib.request.HTTPDigestAuthHandler(password_mgr)
opener = urllib.request.build_opener(handler)

try:
    response = opener.open(url, timeout=10)
    xml_data = response.read().decode('utf-8')
    dom = xml.dom.minidom.parseString(xml_data)
    channels = dom.getElementsByTagName('StreamingChannel')
    
    print(f"Found {len(channels)} channels")
    for ch in channels:
        ch_id = ch.getElementsByTagName('id')[0].firstChild.nodeValue
        ch_name = ch.getElementsByTagName('channelName')[0].firstChild.nodeValue if ch.getElementsByTagName('channelName') else "N/A"
        codec = ch.getElementsByTagName('videoCodecType')[0].firstChild.nodeValue if ch.getElementsByTagName('videoCodecType') else "N/A"
        print(f"ID: {ch_id}, Name: {ch_name}, Codec: {codec}")
except Exception as e:
    print(f"Error: {e}")
