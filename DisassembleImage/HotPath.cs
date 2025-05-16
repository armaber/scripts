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
        var istream = new StreamReader(source);
        var ostream = new StreamWriter(destination);
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
        var body = new List<string>();
        var block = new StringBuilder();
        var istream = new StreamReader(path);
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
        var ostream = new StreamWriter(path);
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
    ImportAddressTable
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
    private static Regex pattern;
    const string FlowAnalysisCookie = "Flow analysis was incomplete, some code may be missing";
    public static Node CreateTree(bool upcall, string delimiter, string path, string key, uint depth, string[] stopSymbols, Dictionary<string, string> retpoline)
    {
        var istream = new StreamReader(path);
        var content = istream.ReadToEnd();
        istream.Close();
        List<string> body = content.Split(delimiter, StringSplitOptions.RemoveEmptyEntries).ToList();
        content = null;
        string address = "";
        var level = LocateHeaderAsHumanReadable(key, body, ref address);
        if (level == -1)
        {
            return null;
        }
        Node tree = new();
        tree.Symbol = key;
        tree.Index = level;
        tree.Address = address;
        if (upcall)
        {
            LocateDependencyRecursiveUpcall(0, depth, ref tree, body);
        }
        else
        {
            LocateDependencyRecursiveDowncall(0, depth, ref tree, body, stopSymbols, retpoline);
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

    private static List<int> LocateBodiesByUpcall(List<string> body, Regex pattern)
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
                            tree[i].Hint == DrawHint.ImportAddressTable);
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

    public static void LocateDependencyRecursiveUpcall(uint current, uint depth, ref Node node, List<string> body)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        current++;
        List<string> depString = new();
        Regex pattern = new($"call    {node.Symbol} \\({node.Address}\\)");
        var idx = LocateBodiesByUpcall(body, pattern);
        if (idx[0] == -1) {
            node.Hint = DrawHint.BodyNotFound;
            return;
        } 
        foreach (var iter in idx)
        {
            string []header = body[iter].Split("\n", 3);
            string address = header[0].Replace("uf ", "");
            string nameOnly = header[1] == FlowAnalysisCookie ?
                              header[2].Substring(0, header[2].IndexOf("\n")) :
                              header[1];
            nameOnly = nameOnly.Substring(0, nameOnly.Length - 1);

            Node dep = new();

            dep.Index = iter;
            dep.Symbol = nameOnly;
            dep.Address = address;
            dep.Hint = DrawHint.HasDependency;
            node.Dependency.Add(dep);
            LocateDependencyRecursiveUpcall(current, depth, ref dep, body);
        }
    }

    public static void LocateDependencyRecursiveDowncall(uint current, uint depth, ref Node node, List<string> body, string[] stopSymbols, Dictionary<string, string> retpoline)
    {
        if (current == depth)
        {
            node.Hint = DrawHint.AtEnd;
            return;
        }
        current++;
        var idx = node.Index;
        List<string> depString = new();
        if (pattern == null)
        {
            pattern = new(@"(call    (?<part>(qword ptr \[\w+!((_imp_|_?guard_dispatch_icall).*)\])|(\w+!.*)))|(jmp     (?<part>qword ptr \[\w+!_imp_.*\]))", RegexOptions.Compiled);
        }
        var match = pattern.Match(body[idx]);
        while (match.Success)
        {
            var part = match.Groups["part"].Value;
            depString.Add(part);
            match = match.NextMatch();
        }
        depString = depString.Distinct().ToList();
        if (depString.Count == 0)
        {
            node.Hint = DrawHint.BodyNotFound;
            return;
        }
        foreach (var iter in depString)
        {
            Node dep = new();

            var nameOnly = iter.Substring(0, iter.LastIndexOf(" (")).Replace("qword ptr [", "");
            dep.Symbol = nameOnly;
            // Some compilers use _guard_dispatch_icall, others without first underscore.
            if (nameOnly.Contains("guard_dispatch_icall"))
            {
                dep.Index = -1;
                dep.Hint = DrawHint.Retpoline;
                if (retpoline.Count > 0)
                {
                    var indirect = GetRetpolineTarget(body[idx], retpoline);
                    dep.Symbol = $"{dep.Symbol} ({indirect})";
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
                    if (Regex.IsMatch(nameOnly, stop))
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
            address = $"uf {address}";
            dep.Index = LocateHeader(address, body, ref nameOnly);
            if (dep.Index == -1)
            {
                dep.Hint = DrawHint.BodyNotFound;
                node.Dependency.Add(dep);
                continue;
            }
            dep.Symbol = nameOnly;
            dep.Hint = DrawHint.HasDependency;
            LocateDependencyRecursiveDowncall(current, depth, ref dep, body, stopSymbols, retpoline);
            node.Dependency.Add(dep);
        }
    }

    private static string GetRetpolineTarget(string section, Dictionary<string, string> retpoline)
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

    private static int LocateHeaderAsHumanReadable(string key, List<string> body, ref string address)
    {
        int i = 0;
        foreach (var iter in body)
        {
            var header = iter.Split("\n", 3);
            if (header[1] == FlowAnalysisCookie)
            {
                header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
            }
            if (header[1] == $"{key}:")
            {
                address = header[0].Replace("uf ", "");
                return i;
            }
            i++;
        }

        return -1;
    }

    private static int LocateHeader(string ufAddress, List<string> body, ref string name)
    {
        int i = 0;
        foreach (var iter in body)
        {
            var header = iter.Split("\n", 3);
            if (header[0] == ufAddress)
            {
                if (header[1] == FlowAnalysisCookie)
                {
                    header[1] = header[2].Substring(0, header[2].IndexOf("\n"));
                }
                name = header[1];
                name = name.Substring(0, name.Length - 1);
                return i;
            }
            i++;
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
