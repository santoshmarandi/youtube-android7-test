#!/usr/bin/env python3
import xml.etree.ElementTree as ET
import sys
import os

def configure(youtube_prefs_path, output_revanced_path):
    hot_config = ""
    hot_hash = ""
    cold_config = ""
    cold_hash = ""

    if os.path.exists(youtube_prefs_path):
        try:
            tree = ET.parse(youtube_prefs_path)
            root = tree.getroot()
            for child in root:
                name = child.attrib.get('name', '')
                if name == 'com.google.android.libraries.youtube.innertube.hot_config_group':
                    hot_config = child.text or ''
                elif name == 'com.google.android.libraries.youtube.innertube.hot_hash_data':
                    hot_hash = child.text or ''
                elif name == 'com.google.android.libraries.youtube.innertube.cold_config_group':
                    cold_config = child.text or ''
                elif name == 'com.google.android.libraries.youtube.innertube.cold_hash_data':
                    cold_hash = child.text or ''
            print(f"Extracted hot_config (len {len(hot_config)}), cold_config (len {len(cold_config)})")
        except Exception as e:
            print(f"Error parsing {youtube_prefs_path}: {e}")
    else:
        print(f"Warning: {youtube_prefs_path} does not exist")

    # Build revanced.xml
    root = ET.Element('map')

    def add_bool(name, val):
        b = ET.SubElement(root, 'boolean')
        b.attrib['name'] = name
        b.attrib['value'] = 'true' if val else 'false'

    def add_str(name, val):
        s = ET.SubElement(root, 'string')
        s.attrib['name'] = name
        s.text = val

    # Core spoof & layout freeze settings
    add_bool('revanced_spoof_app_version', True)
    add_str('revanced_spoof_app_version_target', '19.01.34')
    add_bool('revanced_freeze_layout_updates', True)

    if hot_config:
        add_str('revanced_frozen_hot_config_group', hot_config)
    if hot_hash:
        add_str('revanced_frozen_hot_hash_data', hot_hash)
    if cold_config:
        add_str('revanced_frozen_cold_config_group', cold_config)
    if cold_hash:
        add_str('revanced_frozen_cold_hash_data', cold_hash)

    # Disable annoying prompts
    add_bool('revanced_hide_crowdfunding_box', True)
    add_bool('revanced_hide_floating_microphone', True)

    xml_str = ET.tostring(root, encoding='utf-8')
    with open(output_revanced_path, 'wb') as f:
        f.write(b"<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n")
        f.write(xml_str)
        f.write(b"\n")
    print(f"Generated {output_revanced_path} successfully")

if __name__ == '__main__':
    yt_prefs = sys.argv[1] if len(sys.argv) > 1 else 'youtube.xml'
    out_revanced = sys.argv[2] if len(sys.argv) > 2 else 'revanced.xml'
    configure(yt_prefs, out_revanced)
