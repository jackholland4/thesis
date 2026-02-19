#!/usr/bin/env python3
"""
Download Census TIGER 2010 State Legislative District Lower Chamber files
from the 2010 redistricting cycle and rename them with state abbreviations.

URL: https://www2.census.gov/geo/tiger/TIGER2010/SLDL/2010/
"""

import requests
import re
import os
from pathlib import Path

# FIPS code to state abbreviation mapping
FIPS_TO_STATE = {
    '01': 'AL', '02': 'AK', '04': 'AZ', '05': 'AR', '06': 'CA',
    '08': 'CO', '09': 'CT', '10': 'DE', '11': 'DC', '12': 'FL',
    '13': 'GA', '15': 'HI', '16': 'ID', '17': 'IL', '18': 'IN',
    '19': 'IA', '20': 'KS', '21': 'KY', '22': 'LA', '23': 'ME',
    '24': 'MD', '25': 'MA', '26': 'MI', '27': 'MN', '28': 'MS',
    '29': 'MO', '30': 'MT', '31': 'NE', '32': 'NV', '33': 'NH',
    '34': 'NJ', '35': 'NM', '36': 'NY', '37': 'NC', '38': 'ND',
    '39': 'OH', '40': 'OK', '41': 'OR', '42': 'PA', '44': 'RI',
    '45': 'SC', '46': 'SD', '47': 'TN', '48': 'TX', '49': 'UT',
    '50': 'VT', '51': 'VA', '53': 'WA', '54': 'WV', '55': 'WI',
    '56': 'WY', '60': 'AS', '66': 'GU', '69': 'MP', '72': 'PR',
    '78': 'VI'
}

def download_sldl_files(base_url, output_dir='.'):
    """
    Download all SLDL files from the Census website and rename them.
    
    Args:
        base_url: The Census TIGER directory URL
        output_dir: Directory to save downloaded files (default: current directory)
    """
    # Create output directory if it doesn't exist
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    print(f"Fetching file list from {base_url}...")
    
    try:
        # Fetch the directory listing
        response = requests.get(base_url, timeout=30)
        response.raise_for_status()
        
        # Parse HTML to find .zip files matching the pattern tl_2010_XX_sldl10.zip
        pattern = r'tl_2010_(\d{2})_sldl10\.zip'
        matches = re.findall(pattern, response.text)
        
        if not matches:
            print("No matching files found!")
            return
        
        print(f"Found {len(matches)} files to download\n")
        
        # Download each file
        for fips_code in matches:
            filename = f"tl_2010_{fips_code}_sldl10.zip"
            file_url = base_url.rstrip('/') + '/' + filename
            
            # Get state abbreviation
            state_abbr = FIPS_TO_STATE.get(fips_code, f'FIPS{fips_code}')
            new_filename = f"{state_abbr}_Leg_2010.zip"
            output_file = output_path / new_filename
            
            print(f"Downloading {filename} -> {new_filename}...")
            
            try:
                file_response = requests.get(file_url, timeout=60, stream=True)
                file_response.raise_for_status()
                
                # Write file to disk
                with open(output_file, 'wb') as f:
                    for chunk in file_response.iter_content(chunk_size=8192):
                        f.write(chunk)
                
                file_size = output_file.stat().st_size / (1024 * 1024)  # Convert to MB
                print(f"  ✓ Downloaded {new_filename} ({file_size:.1f} MB)")
                
            except requests.exceptions.RequestException as e:
                print(f"  ✗ Error downloading {filename}: {e}")
        
        print(f"\n✓ Download complete! Files saved to: {output_path.absolute()}")
        
    except requests.exceptions.RequestException as e:
        print(f"Error fetching directory listing: {e}")

if __name__ == "__main__":
    # Census TIGER 2010 SLDL 2010 directory
    CENSUS_URL = "https://www2.census.gov/geo/tiger/TIGER2010/SLDL/2010/"
    
    # You can specify a custom output directory here
    OUTPUT_DIR = "./census_sldl_2010"
    
    print("=" * 70)
    print("Census TIGER SLDL 2010 Downloader")
    print("State Legislative District Lower Chamber (2010 Redistricting)")
    print("=" * 70)
    print()
    
    download_sldl_files(CENSUS_URL, OUTPUT_DIR)