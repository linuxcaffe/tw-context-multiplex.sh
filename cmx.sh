#!/bin/bash

# cmx.sh - Taskwarrior Context Multiplexer
# Provides the 'cmx' command to apply and manage multiple contexts simultaneously
# Version: 1.0

set -e

# Enable debug mode if DEBUG environment variable is set
DEBUG="${DEBUG:-0}"

debug() {
    if [ "$DEBUG" = "1" ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Function to display usage information
usage() {
    cat << EOF
Usage: cmx [COMMAND]

Manage multiple Taskwarrior contexts simultaneously.

Commands:
    cmx                          Refresh cmx context from current cmx.contexts
    cmx context1,context2,...    Set and activate multiple contexts
    cmx +context                 Add a context to the current set
    cmx -context                 Remove a context from the current set
    cmx show                     Show currently active contexts
    cmx none                     Clear all contexts
    cmx help                     Display this help message

Examples:
    cmx work,morning             Activate both work and morning contexts
    cmx +evening                 Add evening context to current set
    cmx -work                    Remove work context from current set
    cmx show                     List active contexts
    cmx none                     Clear all contexts

Debug Mode:
    Run with DEBUG=1 to see detailed execution information:
    DEBUG=1 cmx work,morning

EOF
}

# Function to get all defined context names
get_defined_contexts() {
    debug "Getting defined contexts..."
    task _get rc.context 2>/dev/null | grep -o 'context\.[^.]*\.read' | sed 's/context\.\(.*\)\.read/\1/' || true
}

# Function to check if a context is defined
is_context_defined() {
    local ctx="$1"
    debug "Checking if context '$ctx' is defined..."
    task _get "rc.context.${ctx}.read" >/dev/null 2>&1
}

# Function to get the read filter for a context
get_context_read() {
    local ctx="$1"
    debug "Getting read filter for context '$ctx'..."
    task _get "rc.context.${ctx}.read" 2>/dev/null || echo ""
}

# Function to get the write filter for a context (if defined)
get_context_write() {
    local ctx="$1"
    debug "Getting write filter for context '$ctx'..."
    task _get "rc.context.${ctx}.write" 2>/dev/null || echo ""
}

# Function to get current cmx.contexts value
get_cmx_contexts() {
    debug "Getting current cmx.contexts..."
    task _get rc.cmx.contexts 2>/dev/null || echo ""
}

# Function to build combined filter from multiple contexts
build_combined_filter() {
    local contexts="$1"
    local filter_type="$2"  # "read" or "write"
    local combined=""
    
    debug "Building combined $filter_type filter from contexts: $contexts"
    
    IFS=',' read -ra CTX_ARRAY <<< "$contexts"
    
    for ctx in "${CTX_ARRAY[@]}"; do
        # Trim whitespace
        ctx=$(echo "$ctx" | xargs)
        debug "Processing context: '$ctx'"
        
        if ! is_context_defined "$ctx"; then
            echo "Error: Context '$ctx' is not defined" >&2
            echo "Use 'task context define $ctx <filter>' to define it first" >&2
            return 1
        fi
        
        local filter=""
        if [ "$filter_type" = "read" ]; then
            filter=$(get_context_read "$ctx")
            debug "Read filter for '$ctx': $filter"
        else
            filter=$(get_context_write "$ctx")
            debug "Write filter for '$ctx': $filter"
        fi
        
        if [ -n "$filter" ]; then
            if [ -z "$combined" ]; then
                combined="( $filter )"
            else
                combined="$combined and ( $filter )"
            fi
            debug "Combined filter so far: $combined"
        fi
    done
    
    debug "Final combined filter: $combined"
    echo "$combined"
}

# Function to set the cmx context
set_cmx_context() {
    local contexts="$1"
    
    debug "Setting cmx context with: '$contexts'"
    
    if [ -z "$contexts" ]; then
        # Clear everything
        debug "Clearing all cmx context variables..."
        echo "yes" | task config cmx.contexts "" >/dev/null 2>&1 || true
        echo "yes" | task config context.cmx.read "" >/dev/null 2>&1 || true
        echo "yes" | task config context.cmx.write "" >/dev/null 2>&1 || true
        echo "yes" | task config context "" >/dev/null 2>&1 || true
        echo "Cleared all contexts"
        return 0
    fi
    
    # Build combined filters
    debug "Building combined read filter..."
    local combined_read=$(build_combined_filter "$contexts" "read")
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    debug "Building combined write filter..."
    local combined_write=$(build_combined_filter "$contexts" "write")
    
    # Set the cmx.contexts variable
    debug "Setting cmx.contexts to: $contexts"
    echo "yes" | task config cmx.contexts "$contexts" >/dev/null 2>&1
    
    # Set the context.cmx.read variable
    if [ -n "$combined_read" ]; then
        debug "Setting context.cmx.read to: $combined_read"
        echo "yes" | task config context.cmx.read "$combined_read" >/dev/null 2>&1
    else
        debug "Clearing context.cmx.read (no read filter)"
        echo "yes" | task config context.cmx.read "" >/dev/null 2>&1 || true
    fi
    
    # Set the context.cmx.write variable if there's a write filter
    if [ -n "$combined_write" ]; then
        debug "Setting context.cmx.write to: $combined_write"
        echo "yes" | task config context.cmx.write "$combined_write" >/dev/null 2>&1
    else
        debug "Clearing context.cmx.write (no write filter)"
        echo "yes" | task config context.cmx.write "" >/dev/null 2>&1 || true
    fi
    
    # Set the active context to cmx
    debug "Setting active context to cmx"
    echo "yes" | task config context cmx >/dev/null 2>&1
    
    echo "Activated contexts: $contexts"
}

# Function to add a context to the current set
add_context() {
    local new_ctx="$1"
    local current=$(get_cmx_contexts)
    
    debug "Adding context '$new_ctx' to current set: '$current'"
    
    if ! is_context_defined "$new_ctx"; then
        echo "Error: Context '$new_ctx' is not defined" >&2
        echo "Use 'task context define $new_ctx <filter>' to define it first" >&2
        return 1
    fi
    
    # Check if context is already in the list
    if [[ ",$current," == *",$new_ctx,"* ]]; then
        echo "Context '$new_ctx' is already active"
        return 0
    fi
    
    if [ -z "$current" ]; then
        set_cmx_context "$new_ctx"
    else
        set_cmx_context "$current,$new_ctx"
    fi
}

# Function to remove a context from the current set
remove_context() {
    local remove_ctx="$1"
    local current=$(get_cmx_contexts)
    
    debug "Removing context '$remove_ctx' from current set: '$current'"
    
    if [ -z "$current" ]; then
        echo "No contexts are currently active"
        return 0
    fi
    
    # Remove the context from the comma-separated list
    local new_contexts=$(echo "$current" | tr ',' '\n' | grep -v "^${remove_ctx}$" | paste -sd, -)
    
    debug "New contexts after removal: '$new_contexts'"
    
    if [ "$new_contexts" = "$current" ]; then
        echo "Context '$remove_ctx' was not in the active set"
        return 0
    fi
    
    set_cmx_context "$new_contexts"
}

# Function to show current contexts
show_contexts() {
    debug "Showing current contexts..."
    local current=$(get_cmx_contexts)
    
    if [ -z "$current" ]; then
        echo "No cmx contexts are currently active"
        
        # Check if a regular context is active
        local regular_context=$(task _get rc.context 2>/dev/null || echo "")
        if [ -n "$regular_context" ] && [ "$regular_context" != "cmx" ]; then
            echo "Regular context active: $regular_context"
        fi
    else
        echo "Active cmx contexts: $current"
        echo ""
        echo "Combined read filter:"
        task _get rc.context.cmx.read 2>/dev/null || echo "(none)"
        
        local write_filter=$(task _get rc.context.cmx.write 2>/dev/null || echo "")
        if [ -n "$write_filter" ]; then
            echo ""
            echo "Combined write filter:"
            echo "$write_filter"
        fi
    fi
}

# Function to refresh cmx context from current cmx.contexts
refresh_cmx() {
    debug "Refreshing cmx context..."
    local current=$(get_cmx_contexts)
    
    if [ -z "$current" ]; then
        echo "No cmx contexts defined to refresh"
        return 0
    fi
    
    echo "Refreshing cmx context..."
    set_cmx_context "$current"
}

# Main script logic
main() {
    debug "Starting cmx with arguments: $@"
    
    # Check if task command is available
    if ! command -v task &> /dev/null; then
        echo "Error: 'task' command not found. Please install Taskwarrior." >&2
        exit 1
    fi
    
    debug "Taskwarrior found"
    
    # Parse command
    if [ $# -eq 0 ]; then
        debug "No arguments - refreshing from current cmx.contexts"
        # No arguments - refresh from current cmx.contexts
        refresh_cmx
    elif [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        debug "Showing help"
        usage
    elif [ "$1" = "show" ]; then
        debug "Showing contexts"
        show_contexts
    elif [ "$1" = "none" ]; then
        debug "Clearing all contexts"
        set_cmx_context ""
    elif [[ "$1" == +* ]]; then
        debug "Adding context: ${1:1}"
        # Add context
        add_context "${1:1}"
    elif [[ "$1" == -* ]]; then
        debug "Removing context: ${1:1}"
        # Remove context
        remove_context "${1:1}"
    else
        debug "Setting contexts: $1"
        # Set contexts (comma-separated list)
        set_cmx_context "$1"
    fi
    
    debug "cmx finished"
}

# Run main function
main "$@"
