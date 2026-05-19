import re

with open('/Users/sky/Documents/SkyPaste/Sources/UI/MainView.swift', 'r') as f:
    content = f.read()

# Pattern for pin, delete
content = re.sub(
    r'let selectedURLs = storage\.popoverSelectedURLs\.isEmpty \? \(storage\.popoverHoveredURL != nil \? \[storage\.popoverHoveredURL!\] : \[\]\) : storage\.popoverSelectedURLs',
    r'let selectedURLs = storage.getActivePopoverURLs(for: id)',
    content
)

# Pattern for folder, finder where id is declared in if statement
content = re.sub(
    r'Button\(action: \{\n(\s+)let selectedURLs = storage\.getActivePopoverURLs\(for: id\)\n(\s+)if !selectedURLs\.isEmpty, let id = storage\.hoveredItemID,',
    r'Button(action: {\n\1guard let id = storage.hoveredItemID else { return }\n\1let selectedURLs = storage.getActivePopoverURLs(for: id)\n\2if !selectedURLs.isEmpty,',
    content
)

content = re.sub(
    r'Button\(action: \{\n(\s+)let selectedURLs = storage\.getActivePopoverURLs\(for: id\)\n(\s+)let urlsToActOn = selectedURLs\.isEmpty \? \(storage\.items\.first\(where: \{ \$0\.id == storage\.hoveredItemID \}\)\?\.fileURL\.map \{ \[\$0\] \} \?\? \[\]\) : selectedURLs',
    r'Button(action: {\n\1guard let id = storage.hoveredItemID else { return }\n\1let selectedURLs = storage.getActivePopoverURLs(for: id)\n\2let urlsToActOn = selectedURLs.isEmpty ? (storage.items.first(where: { $0.id == id })?.fileURL.map { [$0] } ?? []) : selectedURLs',
    content
)

with open('/Users/sky/Documents/SkyPaste/Sources/UI/MainView.swift', 'w') as f:
    f.write(content)
