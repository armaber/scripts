"use strict";

function toString(s)
{
    if (typeof s == "string") {
        return s;
    }
    var m = ""
    for (var i of s) {
        m += i + "\n";
    }
    return m;
}

function reloadSymbols(ctl)
{
    var output = ctl.ExecuteCommand(".sympath");

    output = toString(output);
    if (!output.match("https://msdl.microsoft.com/download/symbols")) {
        ctl.ExecuteCommand(".sympath+ srv*https://msdl.microsoft.com/download/symbols");
    }
    ctl.ExecuteCommand(".reload");
}

function invokeScript()
{
    var ctl = host.namespace.Debugger.Utility.Control;
    var dout, output, kinterrupt, first, devobj, gsiv, devext, hid;
    var CTRL = 0;
    var arbiter = new Map();

    reloadSymbols(ctl);

    var output = ctl.ExecuteCommand("!amli find _OSC");

    for (var line of output) {
        if (line.match("\\_SB\..{4}\._OSC")) {
            var pci0 = line.replace("\._OSC","");
 
            hid = ctl.ExecuteCommand("!amli dns /v " + pci0 + "._HID");
            //EISAID("PNP0A08")
            if (hid[2] != "Integer(_HID:Value=0x00000000080ad041[134926401])") {
                continue;
            }

            line = "!amli dns /v " + line;
            dout = ctl.ExecuteCommand(line);
            var disassembly = "!amli u " + dout[2].split("CodeBuff=")[1].split(",")[0];
            dout = ctl.ExecuteCommand(disassembly);
            dout = toString(dout);
            host.diagnostics.debugLog(dout);
            if (dout.match(/ NHPG\(\)/g)) {
                dout = ctl.ExecuteCommand("!amli dns /v " + pci0 + ".NHPG");
                if (dout[0].match("AMLI_DBGERR:")) {
                    dout = ctl.ExecuteCommand("!amli dns /v \\NHPG");
                }
                disassembly = "!amli u " + dout[2].split("CodeBuff=")[1].split(",")[0];
                dout = ctl.ExecuteCommand(disassembly);
                dout = toString(dout);
                host.diagnostics.debugLog(dout);
            }
 
            disassembly = "!amli dns /v " + pci0 + ".SUPP";
            dout = ctl.ExecuteCommand(disassembly);
            if (!dout[0].match("AMLI_DBGERR:")) {
                host.diagnostics.debugLog(dout[2] + "\n");
            }

            disassembly = "!amli dns /v " + pci0 + ".CTRL";
            dout = ctl.ExecuteCommand(disassembly);
            CTRL = parseInt(dout[2].split("\[")[1].split("\]")[0], 10);
            host.diagnostics.debugLog(dout[2] + "\n");

            break;
        }
    }
    output = ctl.ExecuteCommand("!arbiter 4");
    for (var line of output) {
        if (line.match("\(pci\)")) {
            first = "0x" + line.trim().split(" ")[0].substring(8);
            devobj = "0x" + line.trim().split(/\b/)[4];
            arbiter.set(first, devobj);
        }
    }
    output = ctl.ExecuteCommand("!idt");
    for (var line of output) {
        if (line.match("pci!(ExpressRootPortMessageRoutine|ExpressDownstreamSwitchPortInterruptRoutine)")) {
            line = line.replace(/\s+/g, " ").replace(/\: [0-9a-f]{16} /, ": ");
            host.diagnostics.debugLog("\n" + line + "\n");
            kinterrupt = (line.split("KINTERRUPT ")[1].split("\)")[0]);
            dout = ctl.ExecuteCommand("dx ((nt!_KINTERRUPT *)0x" + kinterrupt + ")->ConnectionData->Vectors[0].ControllerInput.Gsiv");
            gsiv = dout[0].split("\: ")[1].split(" ")[0];
            dout = ctl.ExecuteCommand("dx ((nt!_DEVICE_OBJECT *)" + arbiter.get(gsiv) + ")->DeviceExtension");
            devext = dout[0].split("\: ")[1].split(" ")[0];
            dout = ctl.ExecuteCommand("!devext " + devext);
            first = dout[0].replace("PDO Extension, ", "Location: ");
            host.diagnostics.debugLog(first + "\n" + dout[1] + "\n" + dout[3] + "\n" + dout[4] + "\n");
        }
    }
    output = ctl.ExecuteCommand("!sysinfo cpuinfo");
    host.diagnostics.debugLog("\n" + output[5] + "\n" + output[4] + "\n");
}
