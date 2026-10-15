-- Records added to the data of tools/ZarzadzanieKonmi.Seed so that every screen of the manual has something to show:
-- open reminders (overdue and upcoming), a foal without a passport, a purchase with delivery, a boarding fee and two
-- entries in the trash. Dates are relative to today, amounts are in grosze.

INSERT INTO Reminders (Id, HorseId, Kind, DueDate, Title, Status, CreatedAt, UpdatedAt, Version) VALUES
('A0000000-0000-4000-8000-000000000001', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 3), 'Farrier', date('now', '-6 days'), 'Kowal — korekcja', 'Open', datetime('now', '-50 days'), datetime('now', '-50 days'), 1),
('A0000000-0000-4000-8000-000000000002', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 4), 'Vaccination', date('now', '-3 days'), 'Szczepienie przeciw grypie', 'Open', datetime('now', '-180 days'), datetime('now', '-180 days'), 1),
('A0000000-0000-4000-8000-000000000003', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 7), 'Deworming', date('now', '+2 days'), 'Odrobaczanie', 'Open', datetime('now', '-90 days'), datetime('now', '-90 days'), 1),
('A0000000-0000-4000-8000-000000000004', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 6), 'Physio', date('now', '+5 days'), 'Fizjoterapia — kontrola grzbietu', 'Open', datetime('now', '-25 days'), datetime('now', '-25 days'), 1),
('A0000000-0000-4000-8000-000000000005', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 1), 'Vet', date('now', '+6 days'), 'Kontrola weterynaryjna', 'Open', datetime('now', '-24 days'), datetime('now', '-24 days'), 1),
('A0000000-0000-4000-8000-000000000006', (SELECT Id FROM Horses WHERE DeletedAt IS NULL ORDER BY Name LIMIT 1 OFFSET 5), 'Other', date('now', '+21 days'), 'Przegląd siodła', 'Open', datetime('now', '-9 days'), datetime('now', '-9 days'), 1);

INSERT INTO Horses (Id, Name, PassportNumber, IsFoal, Status, FarrierIntervalWeeks, BirthDate, BirthYearOnly, Sex, Color, Breed, CreatedAt, UpdatedAt, Version) VALUES
('B0000000-0000-4000-8000-000000000001', 'Iskierka', NULL, 1, 'Active', 8, date('now', '-13 months', '-15 days'), 0, 'Mare', 'kasztanowata', 'sp', datetime('now', '-13 months'), datetime('now', '-13 months'), 1);

UPDATE Purchases SET DeliveryCost = 15000 WHERE Id = (SELECT Id FROM Purchases ORDER BY PurchaseDate DESC LIMIT 1);

INSERT INTO Purchases (Id, PurchaseDate, ProductName, CategoryId, TotalAmount, DeliveryCost, Assignment, CreatedAt, UpdatedAt, Version) VALUES
('C0000000-0000-4000-8000-000000000001', date('now', 'start of month'), 'Pensjonat — bieżący miesiąc',
 (SELECT Id FROM DictionaryItems WHERE Type = 'PurchaseCategory' AND Value = 'Pensjonat'), 180000, 0, 'SingleHorse', datetime('now'), datetime('now'), 1);
INSERT INTO PurchaseHorses (PurchaseId, HorseId) VALUES
('C0000000-0000-4000-8000-000000000001', (SELECT Id FROM Horses WHERE DeletedAt IS NULL AND IsFoal = 0 ORDER BY Name LIMIT 1 OFFSET 3));

-- The trash lists the roots of deletions: records whose DeletionBatchId is their own id; dependants share it.
UPDATE Notes SET DeletedAt = datetime('now', '-1 days'), DeletionBatchId = Id
WHERE Id = (SELECT Id FROM Notes ORDER BY NoteDate DESC LIMIT 1);
UPDATE VetVisits SET DeletedAt = datetime('now', '-2 days'), DeletionBatchId = Id
WHERE Id = (SELECT Id FROM VetVisits WHERE DeletedAt IS NULL ORDER BY VisitDateTime DESC LIMIT 1 OFFSET 3);
UPDATE VetMedications SET DeletedAt = datetime('now', '-2 days'),
  DeletionBatchId = (SELECT v.DeletionBatchId FROM VetVisits v WHERE v.Id = VetMedications.VetVisitId)
WHERE VetVisitId IN (SELECT Id FROM VetVisits WHERE DeletionBatchId = Id);
