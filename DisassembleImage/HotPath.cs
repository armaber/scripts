using System;
using System.Text;
using System.Text.RegularExpressions;
using System.IO;
using System.Linq;
using System.Collections.Generic;

public class TrimKD
{
    public static void TrimLogFile(string source, string from, bool after, string to, string destination)
    {
        StreamReader istream = new(source);
        StreamWriter ostream = new(destination);
        string line;
        bool found = false;

        while (! istream.EndOfStream)
        {
            line = istream.ReadLine();
            if (line.StartsWith(to))
            {
                break;
            }
            if (found)
            {
                ostream.WriteLine(line);
                continue;
            }
            if (line.StartsWith(from))
            {
                found = true;
                if (! after)
                {
                    ostream.WriteLine(line);
                }
            }
        }
        ostream.Close();
        istream.Close();
    }
}

public class TrimDisassembly
{
    const uint FlowAnalysisLimit = (uint)100E+3;
    const string FlowAnalysisCookie = "Flow analysis was incomplete, some code may be missing";
    const string NoCodeCookie = "No code found, aborting";
    const string CouldntResolveCookie = "Couldn't resolve error at";
    const string SyntaxErrorCookie = "Syntax error at";

    static void LeftTrim(ref string str, Regex pattern)
    {
        str = pattern.Replace(str, "");
    }

    public static void TrimBodies(string delimiter, string path)
    {
        List<string> body = new();
        StringBuilder block = new();
        StreamReader istream = new(path);
        bool bypass;
        string str;
        StringBuilder sb = new();
        Regex pattern = new(@"^[a-z0-9]{8}(`[a-z0-9]{8})? ", RegexOptions.Compiled | RegexOptions.Multiline);

        while (!istream.EndOfStream)
        {
            var line = istream.ReadLine();
            if (line.StartsWith(delimiter))
            {
                str = block.ToString();
                bypass = str.Contains(NoCodeCookie) ||
                         str.Contains(CouldntResolveCookie) ||
                         str.Contains(SyntaxErrorCookie) ||
                         str.Length > FlowAnalysisLimit &&
                         str.Contains(FlowAnalysisCookie);
                if (!bypass)
                {
                    LeftTrim(ref str, pattern);
                    body.Add(str);
                }
                block.Clear();
            }
            block.Append(line);
            block.Append("\n");
        }
        istream.Close();
        if (block.Length > 0)
        {
            str = block.ToString();
            bypass = str.Contains(NoCodeCookie) ||
                     str.Contains(CouldntResolveCookie) ||
                     str.Contains(SyntaxErrorCookie) ||
                     str.Length > FlowAnalysisLimit &&
                     str.Contains(FlowAnalysisCookie);
            if (!bypass)
            {
                LeftTrim(ref str, pattern);
                body.Add(str);
            }
        }
        StreamWriter ostream = new(path);
        foreach (var iter in body)
        {
            ostream.Write(iter);
        }
        ostream.Close();
    }
}

public enum Expand
{
    None,
    Empty,
    ExpandMiddle,
    ExpandLast
}

public enum DrawHint
{
    HasDependency,
    Retpoline,
    AtEnd,
    StopDisassembly,
    BodyNotFound,
    ImportAddressTable,
    Indirect
}

public class Node
{
    public string Symbol = "";
    public string Address = "";
    public int Index;
    public Expand Expand;
    public DrawHint Hint;
    public System.Collections.Generic.List<Node> Dependency = new();
}

public class ParseDisassembly
{
    static Regex _pattern;
    const string FlowAnalysisCookie = "Flow analysis was incomplete, some code may be missing";

    private class IdentifyArgument
    {
        public string Target;
        public string SourceDisasm;
        public uint AboveLimit;
        public Regex CompiledPattern;
    }

    static IdentifyArgument[] _indirect =
    {
        new(){
            Target = @"call    \w+!KeInitializeDpc",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 2
        },
        new(){
            Target = @"call    \w+!KeInitializeThreadedDpc",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 2
        },
        new(){
            Target = @"call    \w+!KeSynchronizeExecution",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!MmMapMdl",
            SourceDisasm = @"lea     r8,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!IoQueueWorkItem",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!IoQueueWorkItemEx",
            SourceDisasm = @"lea     rdx,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]",
            AboveLimit = 5
        },
        new(){
            Target = @"call    \w+!IoRegisterPlugPlayNotification",
            SourceDisasm = @"lea     rax,\[(?<solution>.+) \([0-9a-f]{8}`[0-9a-f]{8}\)\]\n(.+?\n){0,2}[0-9a-f]+?\s+mov     qword ptr \[rsp\+20h\],rax",
            AboveLimit = 5
        }
    };

    public static Node CreateTree(bool upcall, string delimiter, string path, string key, uint depth, string[] stopSymbols, Dictionary<string, string> retpoline)
    {
        StreamReader istream = new(path);
        var content = istream.ReadToEnd();
        istream.Close();
        List<string> body = content.Split(delimiter, StringSplitOptions.RemoveEmptyEntries).ToList();
        content = null;
        string address = "";
        Node tree = new();
        var level = LocateSectionByKeyFunction(key, body, ref address);
        tree.Symbol = key;
        tree.Index = level;
        if (level == -1)
        {
            var levels = LocateSectionByRandomKey(key, body);
            if (levels.Count == 0)
            {
                return null;
            }
            InitializeIndirectRegex();
            foreach (var iter in levels) {
                Node dep = new();
                dep.Index = iter;
                GetSectionHeader(body[iter], ref dep.Symbol, ref dep.Address);
                if (upcall)
                {
                    LocateDependencyRecursiveUpcall(1, depth, ref dep, body);
                }
                else
                {
                    LocateDependencyRecursiveDowncall(1, depth, ref dep, body, stopSymbols, retpoline);
                }
                tree.Dependency.Add(dep);
            }
        } else {
            tree.Address = address;
            InitializeIndirectRegex();
            if (upcall)
            {
                LocateDependencyRecursiveUpcall(0, depth, ref tree, body);
            }
            else
            {
                LocateDependencyRecursiveDowncall(0, depth, ref tree, body, stopSymbols, retpoline);
            }
        }
        if (tree.Dependency.Count != 0)
        {
            AddExpand(tree.Dependency);
        }
        else
        {
            tree.Expand = Expand.None;
        }

        return tree;
    }

    private static void InitializeIndirectRegex()
    {
        foreach (var iter in _indirect)
        {
            iter.CompiledPattern = new($"{iter.SourceDisasm}\\n(.+?\\n){{0,{iter.AboveLimit}}}[0-9a-f]+?\\s+{iter.Target}", RegexOptions.Compiled);
        }
    }

    private static void GetSectionHeader(in string section, ref string symbol, ref string address)
    {
        string []header = section.Split("\n", 3);

        address = header[0].Replace("uf ", "");
        symbol = header[1] == FlowAnalysisCookie ?
                 header[2].Substring(0, header[2].IndexOf("\n")) : header[1];
        symbol = symbol.Substring(0, symbol.Length - 1);
    }

    private static List<int> LocateSectionsByUpcall(in List<string> body, Regex pattern)
    {
        List<int> result = new();

        for (int i = 0; i < body.Count; i++)
        {
            if (pattern.IsMatch(body[i]))
            {
                result.Add(i);
            }
        }
        if (result.Count == 0)
        {
            result.Add(-1);
        }

        return result;
    }

    private static void AddExpand(List<Node> tree)
    {
        Node el = null;
        int i;

        for (i = 0; i < tree.Count; i++)
        {
            bool noArrow = (tree[i].Hint == DrawHint.BodyNotFound ||
                            tree[i].Hint == DrawHint.Retpoline ||
                            tree[i].Hint == DrawHint.AtEnd ||
                            tree[i].Hint == DrawHint.StopDisassembly ||
                            tree[i].Hint == DrawHint.ImportAddressTable ||
                            tree[i].Hint == DrawHint.Indirect);
            if (noArrow)
            {
                tree[i].Expand = Expand.None;
            }
            else
            {
                tree[i].Expand = Expand.ExpandLast;
                if (el != null)
                {
                    el.Expand = Expand.ExpandMiddle;
                }
                el = tree[i];
            }
            if (tree[i].Dependency.Count != 0)
            {
                AddExpand(tree[i].Dependency);
            }
        }
        for (i = tree.Count - 1; i >= 0 && tree[i].Expand == Expand.None; i--) ;
        for (i++; i < tree.Count; i++)
        {
            tree[i].Expand = Expand.Empty;
        }
    }

    public static void LocateDependencyRecursiveUpcall(uint current, uint depth, ref Node node, in List<string> body)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        current++;
        Regex pattern = new($"call    {node.Symbol} \\({node.Address}\\)");
        var idx = LocateSectionsByUpcall(body, pattern);
        if (idx[0] == -1) {
            node.Hint = DrawHint.BodyNotFound;
            return;
        }
        foreach (var iter in idx)
        {
            Node dep = new();

            dep.Index = iter;
            GetSectionHeader(body[iter], ref dep.Symbol, ref dep.Address);
            dep.Hint = DrawHint.HasDependency;
            node.Dependency.Add(dep);
            LocateDependencyRecursiveUpcall(current, depth, ref dep, body);
        }
    }

    public static void LocateDependencyRecursiveDowncall(uint current, uint depth, ref Node node, in List<string> body, in string[] stopSymbols, in Dictionary<string, string> retpoline)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        IdentifyArgument indirect = new();
        current++;
        var idx = node.Index;
        List<string> deplist = new();
        if (_pattern == null)
        {
            _pattern = new(@"(call    (?<partial>(qword ptr \[\w+!((_imp_|_?guard_dispatch_icall).*)\])|(\w+!.*)))|(jmp     (?<partial>qword ptr \[\w+!_imp_.*\]))", RegexOptions.Compiled);
        }
        var match = _pattern.Match(body[idx]);
        while (match.Success)
        {
            var part = match.Groups["partial"].Value;
            deplist.Add(part);
            match = match.NextMatch();
        }
        deplist = deplist.Distinct().ToList();
        if (deplist.Count == 0)
        {
            node.Hint = DrawHint.BodyNotFound;
            return;
        }
        foreach (var iter in deplist)
        {
            Node dep = new();

            var func = iter.Substring(0, iter.LastIndexOf(" (")).Replace("qword ptr [", "");
            dep.Symbol = func;
            // Some compilers use _guard_dispatch_icall, others without first underscore.
            if (func.Contains("guard_dispatch_icall"))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.Retpoline;
                if (retpoline.Count > 0)
                {
                    var repstr = GetRetpolineTarget(body[idx], retpoline);
                    dep.Symbol = $"{dep.Symbol} ({repstr})";
                }
            }
            else if (MatchCallIndirect($"call    {iter}", ref indirect))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.Indirect;
                var indstr = GetIndirectSource(body[idx], indirect);
                if (indstr != "")
                {
                    dep.Symbol = $"{dep.Symbol} ({indstr})";
                }
            }
            else if (iter.Contains("qword ptr ["))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.ImportAddressTable;
            }
            else
            {
                foreach (var stop in stopSymbols)
                {
                    if (Regex.IsMatch(func, stop))
                    {
                        dep.Index = -1;
                        dep.Hint = DrawHint.StopDisassembly;
                        break;
                    }
                }
            }
            if (dep.Index == -1)
            {
                node.Dependency.Add(dep);
                continue;
            }
            var address = iter.Substring(iter.LastIndexOf(" (") + 2).Replace(")", "");
            dep.Address = address;
            dep.Index = LocateSectionByAddress(address, body, ref func);
            if (dep.Index == -1)
            {
                dep.Hint = DrawHint.BodyNotFound;
                node.Dependency.Add(dep);
                continue;
            }
            dep.Symbol = func;
            dep.Hint = DrawHint.HasDependency;
            LocateDependencyRecursiveDowncall(current, depth, ref dep, body, stopSymbols, retpoline);
            node.Dependency.Add(dep);
        }
    }

    private static bool MatchCallIndirect(string call, ref IdentifyArgument arg)
    {
        foreach (var iter in _indirect)
        {
            if (Regex.IsMatch(call, iter.Target))
            {
                arg = iter;
                return true;
            }
        }

        return false;
    }

    private static string GetIndirectSource(in string section, in IdentifyArgument arg)
    {
        List<string> result = new();
        var match = arg.CompiledPattern.Match(section);
        while (match.Success)
        {
            var str = match.Groups["solution"].Value;
            match = match.NextMatch();
            result.Add(str);
        }

        return string.Join(",", result);
    }


    private static string GetRetpolineTarget(in string section, in Dictionary<string, string> retpoline)
    {
        List<string> source = new();
        var match = Regex.Match(section, @"mov     rax,qword ptr \[(\w+!.+?)\s.+?\][\s\S]+?call\s+\w+!_?guard_dispatch_icall");
        while (match.Success)
        {
            source.Add(match.Groups[1].Value);
            match = match.NextMatch();
        }
        if (source.Count == 0)
        {
            return "N/A";
        }
        source = source.Distinct().ToList();
        List<string> target = new();
        foreach (var iter in source)
        {
            try
            {
                if (retpoline != null)
                {
                    target.Add($"{iter}={retpoline[iter]}");
                }
                else
                {
                    target.Add(iter);
                }
            }
            catch (KeyNotFoundException)
            {
                target.Add(iter);
            }
        }

        return string.Join(",", target);
    }

    private static int LocateSectionByKeyFunction(string key, in List<string> body, ref string address)
    {
        for (int i = 0; i < body.Count; i++)
        {
            var header = body[i].Split("\n", 3);
            if (header[1] == FlowAnalysisCookie)
            {
                header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
            }
            if (header[1] == $"{key}:")
            {
                address = header[0].Replace("uf ", "");
                return i;
            }
        }

        return -1;
    }

    private static List<int> LocateSectionByRandomKey(string key, in List<string> body)
    {
        List<int> result = new();

        for (int i = 0; i < body.Count; i++)
        {
            if (body[i].Contains(key))
            {
                result.Add(i);
            }
        }

        return result;
    }

    private static int LocateSectionByAddress(string address, in List<string> body, ref string name)
    {
        for (int i = 0; i < body.Count; i ++)
        {
            var header = body[i].Split("\n", 3);
            if (header[0] == $"uf {address}")
            {
                if (header[1] == FlowAnalysisCookie)
                {
                    header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
                }
                name = header[1];
                name = name.Substring(0, name.Length - 1);
                return i;
            }
        }

        return -1;
    }

    public static int GetTreeCumulatedDependecies(Node tree)
    {
        var count = tree.Dependency.Count;

        foreach (var dep in tree.Dependency)
        {
            if (dep.Dependency.Count > 0)
            {
                count += GetTreeCumulatedDependecies(dep);
            }
        }

        return count;
    }
}
