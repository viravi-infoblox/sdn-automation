#!/usr/bin/env python3
"""
SDN Agent POC - Master Runner
Executes the complete POC workflow:
1. Parse OpenAPI spec
2. Recognize patterns
3. Map to plugins
4. Generate Perl code
"""

import sys
import subprocess
from pathlib import Path
from datetime import datetime


class POCRunner:
    """Execute the complete POC workflow"""
    
    def __init__(self, poc_dir: str):
        self.poc_dir = Path(poc_dir)
        self.scripts = [
            ("OpenAPI Parser", "02_openapi_parser.py"),
            ("Pattern Recognizer", "03_pattern_recognizer.py"),
            ("Plugin Mapper", "04_plugin_mapper.py"),
            ("Code Generator", "05_code_generator.py"),
        ]
        
    def run_script(self, name: str, script: str) -> bool:
        """Run a single Python script"""
        script_path = self.poc_dir / script
        
        if not script_path.exists():
            print(f"❌ Script not found: {script_path}")
            return False
        
        print(f"\n{'='*70}")
        print(f"Running: {name}")
        print(f"{'='*70}")
        
        try:
            result = subprocess.run(
                [sys.executable, str(script_path)],
                cwd=str(self.poc_dir),
                capture_output=False,
                text=True
            )
            
            if result.returncode != 0:
                print(f"❌ {name} failed with exit code {result.returncode}")
                return False
            
            return True
            
        except Exception as e:
            print(f"❌ Error running {name}: {e}")
            return False
    
    def run_all(self):
        """Run all scripts in sequence"""
        start_time = datetime.now()
        
        print("\n" + "="*70)
        print("SDN Agent POC - Complete Workflow Execution")
        print("="*70)
        print(f"Started: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"POC Directory: {self.poc_dir}")
        
        success_count = 0
        
        for name, script in self.scripts:
            if self.run_script(name, script):
                success_count += 1
            else:
                print(f"\n❌ POC workflow failed at step: {name}")
                return False
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        print("\n" + "="*70)
        print("POC Workflow Completed Successfully!")
        print("="*70)
        print(f"Completed: {end_time.strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"Duration: {duration:.2f} seconds")
        print(f"Steps Executed: {success_count}/{len(self.scripts)}")
        
        # Show generated files
        self.show_results()
        
        return True
    
    def show_results(self):
        """Display generated artifacts"""
        print("\n" + "="*70)
        print("Generated Artifacts")
        print("="*70)
        
        artifacts = [
            ("Parsed API", "parsed_api.json"),
            ("Classified Endpoints", "classified_endpoints.json"),
            ("Plugin Mappings", "plugin_mappings.json"),
            ("Client Module", "generated/Client/Meraki_Generated.pm"),
            ("Server Module", "generated/Server/Meraki_Generated.pm"),
        ]
        
        for name, path in artifacts:
            file_path = self.poc_dir / path
            if file_path.exists():
                size = file_path.stat().st_size
                print(f"✓ {name:25} : {path:50} ({size:,} bytes)")
            else:
                print(f"✗ {name:25} : {path:50} (NOT FOUND)")
        
        # Count lines of generated code
        client_file = self.poc_dir / "generated/Client/Meraki_Generated.pm"
        server_file = self.poc_dir / "generated/Server/Meraki_Generated.pm"
        
        if client_file.exists() and server_file.exists():
            with open(client_file, 'r') as f:
                client_lines = len(f.readlines())
            with open(server_file, 'r') as f:
                server_lines = len(f.readlines())
            
            print("\n" + "-"*70)
            print(f"Total Lines of Generated Code: {client_lines + server_lines:,}")
            print(f"  - Client Module: {client_lines:,} lines")
            print(f"  - Server Module: {server_lines:,} lines")


def main():
    """Main execution"""
    # Get POC directory
    script_dir = Path(__file__).parent
    
    runner = POCRunner(str(script_dir))
    
    try:
        success = runner.run_all()
        sys.exit(0 if success else 1)
        
    except KeyboardInterrupt:
        print("\n\n⚠ POC workflow interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
