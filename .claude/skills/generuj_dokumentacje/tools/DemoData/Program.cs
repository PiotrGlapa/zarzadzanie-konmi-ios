using System.Collections;
using System.Reflection;
using System.Resources;
using Microsoft.Data.Sqlite;

// Usage: DemoData <path to konie.db>
//        DemoData --fonts <Wpf.Ui.dll> <output folder>   (the icon fonts of the application, for the manual's HTML)
if (args.Length == 3 && args[0] == "--fonts")
{
    return ExtractFonts(args[1], args[2]);
}

if (args.Length != 1 || !File.Exists(args[0]))
{
    Console.Error.WriteLine("Użycie: DemoData <ścieżka do konie.db> | DemoData --fonts <Wpf.Ui.dll> <folder>");
    return 1;
}

using var connection = new SqliteConnection($"Data Source={args[0]};Pooling=False");
connection.Open();
using var transaction = connection.BeginTransaction();
using (var command = connection.CreateCommand())
{
    command.Transaction = transaction;
    command.CommandText = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "demo-data.sql"));
    command.ExecuteNonQuery();
}

transaction.Commit();
Console.WriteLine("Dodano dane pokazowe (terminy, źrebię, dostawa, pensjonat, kosz).");
return 0;

// The Fluent System Icons fonts are WPF resources of Wpf.Ui.dll (Wpf.Ui.g.resources, "resources/fonts/*.ttf").
static int ExtractFonts(string assemblyPath, string outputFolder)
{
    var assembly = Assembly.LoadFile(Path.GetFullPath(assemblyPath));
    using var resources = assembly.GetManifestResourceStream("Wpf.Ui.g.resources");
    if (resources is null)
    {
        Console.Error.WriteLine("Brak zasobu Wpf.Ui.g.resources.");
        return 1;
    }

    Directory.CreateDirectory(outputFolder);
    var count = 0;
    using var reader = new ResourceReader(resources);
    foreach (DictionaryEntry entry in reader)
    {
        var name = (string)entry.Key;
        if (!name.EndsWith(".ttf", StringComparison.OrdinalIgnoreCase) || entry.Value is not Stream stream)
        {
            continue;
        }

        using var file = File.Create(Path.Combine(outputFolder, Path.GetFileName(name)));
        stream.CopyTo(file);
        count++;
    }

    Console.WriteLine($"Zapisano czcionki: {count}.");
    return count > 0 ? 0 : 1;
}
