#!/usr/bin/env python3
import sys
import os
import subprocess
import shutil

# ANSI Color Codes for beautiful CLI output
GREEN = "\033[92m"
BLUE = "\033[94m"
YELLOW = "\033[93m"
RED = "\033[91m"
BOLD = "\033[1m"
RESET = "\033[0m"

def print_header():
    print(f"{BOLD}{BLUE}================================================================================{RESET}")
    print(f"{BOLD}{BLUE}  TinyMetal Project CLI Manager                                                 {RESET}")
    print(f"{BOLD}{BLUE}================================================================================{RESET}")

def print_help():
    print_header()
    print(f"{BOLD}Available Commands:{RESET}\n")
    
    # Table header
    print(f"+---------------+----------------------------------------------------------------+")
    print(f"| {BOLD}Command{RESET}       | {BOLD}Description{RESET}                                                     |")
    print(f"+---------------+----------------------------------------------------------------+")
    
    commands = [
        ("setup", "Configure the CMake build system for macOS or iOS."),
        ("build", "Build the selected platform targets (Debug/Release)."),
        ("run", "Build and launch the macOS application bundle."),
        ("tool", "Build and run the standalone tiny-mesh-tool."),
        ("shaders", "Compile the HelloTriangleShaders.metal source into default.metallib."),
        ("ci", "Execute full validation check (Shaders compile + App build + Tool execution)."),
        ("clean", "Delete all project build files and cache directories."),
    ]
    
    for cmd, desc in commands:
        print(f"| {GREEN}{cmd:<13}{RESET} | {desc:<62} |")
        
    print(f"+---------------+----------------------------------------------------------------+")
    print()
    
    print(f"{BOLD}Global Options:{RESET}")
    print(f"  --platform   Target platform: {BOLD}macos{RESET} or {BOLD}ios{RESET} (default: macos)")
    print(f"  --config     Configuration:   {BOLD}Debug{RESET} or {BOLD}Release{RESET} (default: Debug)")
    print(f"  --help, -h   Show this help table")
    print()
    print(f"{BOLD}Examples:{RESET}")
    print(f"  python3 manage.py setup --platform macos")
    print(f"  python3 manage.py build")
    print(f"  python3 manage.py run")
    print(f"  python3 manage.py ci")
    print()

def run_proc(cmd, cwd=None):
    print(f"{BOLD}{BLUE}Executing:{RESET} {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"\n{BOLD}{RED}Error: Command failed with exit code {e.returncode}{RESET}")
        sys.exit(e.returncode)

def get_build_dir(platform):
    return os.path.join("build", platform.lower())

def setup_cmd(platform):
    build_dir = get_build_dir(platform)
    platform_name = "macOS" if platform.lower() == "macos" else "iOS"
    
    print(f"{BOLD}{GREEN}Configuring CMake for {platform_name}...{RESET}")
    cmd = [
        "cmake",
        "-S", ".",
        "-B", build_dir,
        "-G", "Xcode",
        f"-DTINYMETAL_PLATFORM={platform_name}",
        "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
    ]
    run_proc(cmd)
    print(f"{BOLD}{GREEN}Configuration complete. Files written to {build_dir}{RESET}\n")

def build_cmd(platform, config, target=None):
    build_dir = get_build_dir(platform)
    if not os.path.exists(build_dir):
        print(f"{BOLD}{YELLOW}Build folder {build_dir} not found. Running setup first...{RESET}")
        setup_cmd(platform)
        
    print(f"{BOLD}{GREEN}Building target(s) for {platform} [{config}]...{RESET}")
    cmd = ["cmake", "--build", build_dir, "--config", config]
    if target:
        cmd.extend(["--target", target])
    run_proc(cmd)
    print(f"{BOLD}{GREEN}Build completed successfully.{RESET}\n")

def clean_cmd():
    print(f"{BOLD}{YELLOW}Cleaning build folders...{RESET}")
    if os.path.exists("build"):
        shutil.rmtree("build")
        print(f"{BOLD}{GREEN}Cleaned build directory.{RESET}")
    else:
        print(f"No build directory found.")

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ["-h", "--help", "help"]:
        print_help()
        sys.exit(0)
        
    command = sys.argv[1].lower()
    
    # Parse options
    platform = "macos"
    config = "Debug"
    
    args = sys.argv[2:]
    i = 0
    while i < len(args):
        if args[i] == "--platform":
            if i + 1 < len(args):
                platform = args[i+1].lower()
                i += 2
            else:
                print(f"{BOLD}{RED}Error: --platform requires an argument{RESET}")
                sys.exit(1)
        elif args[i] == "--config":
            if i + 1 < len(args):
                config = args[i+1]
                i += 2
            else:
                print(f"{BOLD}{RED}Error: --config requires an argument (Debug/Release){RESET}")
                sys.exit(1)
        else:
            print(f"{BOLD}{RED}Error: Unknown argument {args[i]}{RESET}")
            sys.exit(1)
            
    if platform not in ["macos", "ios"]:
        print(f"{BOLD}{RED}Error: Unsupported platform '{platform}'. Use 'macos' or 'ios'.{RESET}")
        sys.exit(1)
        
    if command == "setup":
        setup_cmd(platform)
    elif command == "build":
        build_cmd(platform, config)
    elif command == "run":
        if platform == "ios":
            print(f"{BOLD}{RED}Error: Running iOS directly from CLI is not supported. Please open build/ios/TinyMetal.xcodeproj in Xcode.{RESET}")
            sys.exit(1)
        build_cmd(platform, config, target="run")
    elif command == "tool":
        if platform == "ios":
            print(f"{BOLD}{RED}Error: tiny-mesh-tool is macOS only.{RESET}")
            sys.exit(1)
        build_cmd(platform, config, target="run-tool")
    elif command == "shaders":
        build_cmd(platform, config, target="compileshaders")
    elif command == "ci":
        if platform == "ios":
            print(f"{BOLD}{RED}Error: CI target is macOS only (due to tool execution).{RESET}")
            sys.exit(1)
        build_cmd(platform, config, target="ci")
    elif command == "clean":
        clean_cmd()
    else:
        print(f"{BOLD}{RED}Error: Unknown command '{command}'. Use -h for help.{RESET}")
        sys.exit(1)

if __name__ == "__main__":
    main()
