module Picotool

using picotool_jll: picotool, pico_udev

"""
    install_udev(;dry=true)

Installs the udev rules for Raspberry Pi Picos.

Keyword arguments:
 * `dry`: Whether to do a dry run. When set to `true`, no actions other than downloading are taken. Set to `false` to change your system.

`install_udev` will abort if the target file already exists. Check that the existing udev rule is correct for your
devices and either use the existing rules, or remove the file to try again.

!!! warn "sudo"
    The rules are installed system wide, into `/etc/udev/rules.d/$(basename(pico_udev))`. This requires `sudo`
    permissions, which is why this needs to be done manually. In addition, this requires `udevadm`.
"""
function install_udev(;dry=true)
    !Sys.islinux() && throw(ArgumentError("This command can only be used on Linux!"))
    udevname = basename(pico_udev)
    installpath = "/etc/udev/rules.d/$udevname"
    if ispath(installpath)
        @warn "udev rule file already exists - aborting."
        return
    end

    dry && @info "Doing a dry run - no changes will occur."
    !dry && (@warn "Doing a live run - your system will be affected."; sleep(5))
    println()
    
    mktemp() do dlpath, dlio
        @info "Fixing broken MODE of udev file..."
        udevdata = read(pico_udev, String)
        patched = replace(udevdata, r"MODE=\"\d+\"" => s"MODE=\"0660\"")
        @info "Changed MODE to 0660"
        write(dlio, patched)
        flush(dlio)
        @info "Installing rules file to `/etc/udev/rules.d/$udevname`"
        mvcmd = `sudo install -o root -g root -m 0664 $dlpath $installpath`
        @info "Installing rules" Cmd=mvcmd
        !dry && run(mvcmd)

        udevadmctl = `sudo udevadm control --reload-rules`
        @info "Reloading rules" Cmd=udevadmctl
        !dry && run(udevadmctl)

        udevadmtgr = `sudo udevadm trigger`
        @info "Triggering udev events" Cmd=udevadmtgr
        !dry && run(udevadmtgr)
    end
    @info "Done!"
    @info "The udev rules included by Raspberry Pi only give access to the `plugdev` user group; make sure to add yourself to that."
    nothing
end

"""
    help_cmd([command])

Print out the `help` section provided by the `picotool` binary.
The printed flags can only be used when using the `picotool` binary directly.

You can pass one of the listed commands to this function to print the help associated with that
command from the CLI tool as well.
"""
function help_cmd(command=nothing)
    cmd = command isa Nothing ? `` : `$command`
    proc = picotool() do b
        run(`$b help $cmd`)
    end
    wait(proc)
    nothing
end

@enum Reboot Application USB

"""
    reboot!([type::Reboot=Application]; force = true, bus = nothing, address = nothing)

Reboot an attached device into either the loaded application or the BOOTSEL mode, if supported.

 * `force`   : Force a device not in BOOTSEL but running compatible code to reset.
 * `bus`     : Specify the device bus.
 * `address` : Specify the device address.
"""
function reboot!(type::Reboot=Application; force=true, bus=nothing, address=nothing)
    f = if force
        `-F`
    else
        ``
    end
    b = bus isa Nothing ? `` : `--bus $bus`
    add = bus isa Nothing ? `` : `--address $address`
    t = type == Application ? `-a` : `-u`
    picotool() do x
        run(Cmd(`$x reboot $t $b $add $f`; ignorestatus=true))
    end
    nothing
end

@enum PicoInfo Basic Pins Device Build AllInfo
"""
    info([type::PicoInfo=Basic]; force = true, reboot = false, bus = nothing, address = nothing, path = nothing)

Print diagnostic information for the attached device, or the file located at `path` if given.

 * `type`    : One of `Basic`, `Pins`, `Device`, `Build`, `AllInfo`
 * `force`   : Force a device not in BOOTSEL but running compatible code to reset.
 * `reboot`  : Once the command is finished, reboot the device into application mode.
 * `bus`     : Specify the device bus.
 * `address` : Specify the device address.
 * `path`    : A file to retrieve the given information from.
"""
function info(type::PicoInfo=Basic; force=true, reboot=false, bus=nothing, address=nothing, path=nothing)
    f = force ? (reboot ? `-f` : `-F`) : ``
    b = bus isa Nothing ? `` : `--bus $bus`
    add = bus isa Nothing ? `` : `--address $address`
    file = path isa Nothing ? `` : `$path` 
    t = if type == Basic
        `-b`
    elseif type == Pins
        `-p`
    elseif type == Device
        `-d`
    elseif type == Build
        `-l`
    elseif type == AllInfo
        `-a`
    end
    !(file isa Nothing) && !isempty(f) && throw(ArgumentError("Cannot force a reboot on a file!"))
    !(file isa Nothing) && (!isempty(b) || !isempty(add)) && throw(ArgumentError("Cannot specify both a file and a Pi!"))
    picotool() do x
        run(Cmd(`$x info $t $b $add $file $f`; ignorestatus=true))
    end
    nothing
end

"""
    verify(filename; force = true, reboot = false, bus = nothing, address = nothing,
                     range = nothing, offset = nothing)

Verify the data on the device by comparing it to the data from `filename`.

 * `force`   : Force a device not in BOOTSEL but running compatible code to reset.
 * `reboot`  : Once the command is finished, reboot the device into application mode.
 * `bus`     : Specify the device bus.
 * `address` : Specify the device address.
 * `range`   : A `AbstractUnitRange{<:Integer}` specifying the sub range of memory to verify.
 * `offset`  : Specify the load address when comparing with a BIN file.
"""
function verify(filename; force=false, reboot=false, bus=nothing, address=nothing,
                          range::Union{AbstractUnitRange{<:Integer},Nothing}=nothing, offset=nothing)
    f = force ? (reboot ? `-F` : `-f`) : ``
    b = bus isa Nothing ? `` : `--bus $bus`
    add = bus isa Nothing ? `` : `--address $address`
    isfile(filename) || throw(ArgumentError("There is no file at `$filename`!"))
    fileisbin = endswith(filename, ".bin")
    r = range isa Nothing ? `` : `-r 0x$(string(first(range); base=16)) 0x$(string(last(range); base=16))`
    o = offset isa Nothing ? (fileisbin ? `-o 0x10000000` : ``) : `-o 0x$(string(offset; base=16))`
    !(offset isa Nothing) && !fileisbin && throw(ArgumentError("Offset can only be specified for BIN files!"))
    picotool() do x
        run(Cmd(`$x verify $b $add $f $filename $r $o`; ignorestatus=true))
    end
    nothing
end

@enum SaveData Program AllData

"""
    save(filename; data = Program, force = true, reboot = false, bus = nothing, address = nothing)

Save the requested data from the device and store it in `filename`. `data` must be either `Program`,
`AllData` or a `AbstractUnitRange{<:Integer}`.

!!! info "Ranges"
    Note that UF2s always store a complete 256 byte-aligned blocks of 256 bytes and the range
    is expanded accordingly.

 * `force`   : Force a device not in BOOTSEL but running compatible code to reset.
 * `reboot`  : Once the command is finished, reboot the device into application mode.
 * `bus`     : Specify the device bus.
 * `address` : Specify the device address.
"""
function save(filename; data::Union{SaveData,AbstractUnitRange{<:Integer}}=Program,
                        force=true, reboot=false, bus=nothing, address=nothing)
    f = force ? (reboot ? `-f` : `-F`) : ``
    b = bus isa Nothing ? `` : `--bus $bus`
    add = bus isa Nothing ? `` : `--address $address`
    isfile(filename) && throw(ArgumentError("There is already a file at `$filename`!"))
    _, ext = splitext(filename)
    (isempty(ext) || !(ext in (".elf", ".uf2", ".bin"))) && throw(ArgumentError("File extension must be one of `elf`, `uf2` or `bin`!"))
    d = if data == Program
        `-p`
    elseif data == AllData
        `-a`
    elseif data isa AbstractUnitRange{<:Integer}
        `-r 0x$(string(first(range); base=16)) 0x$(string(last(range); base=16))`
    end
    picotool() do x
        run(Cmd(`$x save $d $b $add $f $filename`; ignorestatus=true))
    end
    nothing
end

"""
    version(;semantic=false)

Print the version of `picotool`.

 * `semantic = true` : Return the version of `picotool` as a `VersionNumber` instead of printing.
"""
function version(;semantic=false)
    s = semantic ? `-s` : ``
    p = Pipe()
    picotool() do x
        run(pipeline(`$x version $s`; stdout=p); wait=false)
    end
    output = readavailable(p)
    if semantic
        return VersionNumber(String(output))
    else
        write(stdout, output)
    end
    nothing
end

@enum OverWrite Always NoOverWrite NoOverWriteUnsafe

"""
    load!(filename; force = true, reboot = true, bus = nothing, address = nothing, update = true
                    verify = true, execute = false, offset = nothing, overwrite = Always)

Load the file located at `filename` onto the device.

 * `force`   : Force a device not in BOOTSEL but running compatible code to reset.
 * `reboot`  : Once the command is finished, reboot the device into application mode.
 * `bus`     : Specify the device bus.
 * `address` : Specify the device address.
 * `update`  : Skip writing flash sectors that already contain identical data.
 * `verify`  : Verify the data was written correctly.
 * `execute` : Attempt to execute the downloaded file as a program after load.
 * `offset`  : Specify the load address for a BIN file.

`overwrite` can take the following values:

 * `Always`            : Overwrite all data.
 * `NoOverWrite`       : When writing flash data, do not overwrite an existing program in flash. If `picotool` cannot
    determine the size/presence of a program in flash, the command fails.
 * `NoOverWriteUnsafe` : When writing flash data, do not overwrite an existing program in flash. If `picotool` cannot
    determine the size/presence of a program in flash, the load continues anyway.
"""
function load!(filename; force=true, reboot=true, bus=nothing, address=nothing, update=false, verify=true,
                        execute=false, offset=nothing, overwrite=Always)
    f = force ? (reboot ? `-f` : `-F`) : ``
    b = bus isa Nothing ? `` : `--bus $bus`
    add = bus isa Nothing ? `` : `--address $address`
    isfile(filename) || throw(ArgumentError("There is no file at `$filename`!"))
    n = overwrite == Always ? `` : 
        overwrite == NoOverWrite ? `-n` : 
        overwrite == NoOverWriteUnsafe ? `-N` : throw(ArgumentError("Unknown overwrite specification: $overwrite"))
    u = update ? `-u` : ``
    v = verify ? `-v` : ``
    x = execute ? `-x` : ``
    o = offset isa Nothing ? `` : `-o $offset`
    !(offset isa Nothing) && !endswith(filename, ".bin") && throw(ArgumentError("Only BIN files can be offset!"))
    picotool() do e
        run(Cmd(`$e load $n $u $v $x $filename $o $b $add $f`; ignorestatus=true))
    end
    nothing
end

end # module Picotool
