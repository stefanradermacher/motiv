<!--
Texts of the English manual. `swift scripts/make_manual.swift en` turns them into the PDF.
The format is described in de.md.
-->

Dokumenttitel: Motiv – Manual
Thema: Image and gallery viewer for macOS
Untertitel: Manual for the image and gallery viewer for macOS
Leitsatz: Your folders, your images.
Einleitung: View images where they are: with overview, single image view, information and comparison.
Free, ad-free and without data collection.

# About This Manual

Motiv is a plain image and gallery viewer for macOS, made for collections of images in folders. It shows images where they are: no library, no import and no sign-in. In a few chapters, this manual describes what Motiv can do and how to use it.

## What Motiv Stands For

- Works directly with your folders; nothing is imported or copied
- Does not modify files; rotating and flipping affect the view only
- Free and open source under the Apache License 2.0
- No ads, no tracking, no data collection
- Apple frameworks only, no third-party components
- German and English

# Folders and Favourites

Motiv does not display any library, only your folders. Add a folder with “File → Add Folder …” or drag it onto the Motiv icon in the Dock. It then appears in the sidebar with all its subfolders.

## Why Grant Access to Folders?

Like every app from the App Store, Motiv may only read what you chose. If you open a single image from the Finder, Motiv shows it right away; it sees the images next to it only once you grant access to the folder with “Grant Folder Access …” in the title bar. Motiv remembers the access, for reading only.

## Favourites

Bring deeply nested folders to the top of the sidebar as favourites, from the context menu or with ⌃⌘T. Clicking the x next to a name removes a folder or favourite from the sidebar; everything on disk stays as it is.

## The Folder Strip

Above the thumbnails, a strip shows the subfolders of the current folder with their names and image counts, and the parent folder first. A click opens a folder. The strip can be dragged taller and scrolled sideways with the mouse wheel. With “Include Subfolders”, the overview also shows all images of the subfolders.

# The Overview

The overview shows the images and videos of a folder as thumbnails. Set their size with the slider in the toolbar, with ⌘+ and ⌘- or with two fingers on the trackpad; ⌘0 restores the default size.

![The overview with folders, folder strip and thumbnails](docs/screenshots/en/1-overview.jpg)

## Sorting and Finding

Sort by name, capture date, modification date, size or kind. To find an image, simply type the beginning of its name. The arrow keys move through the thumbnails, Page Up and Page Down move a page at a time, and ⇧ extends the selection.

## From the Overview

A double-click or the Return key shows an image large. The context menu opens images in Preview or another app, shows them in the Finder, shares them or compares the selected images.

# The Single Image View

In the single image view, page through the folder with the arrow keys, the space bar or with two fingers on the trackpad. Esc returns to the overview; a strip at the bottom shows the neighbouring images. With ⌥⌘F the image fills the whole screen, without bars and without a pointer.

![The single image view with information in the sidebar](docs/screenshots/en/2-viewer.jpg)

## Zooming

An image first fits the window. A double-click shows it at actual size at the point clicked, a second one fits it again. The percentage in the toolbar fits to width or height or picks a zoom level. Motiv loads very large images at full resolution only when you zoom in, so it stays smooth.

## Rotating and Flipping

Rotating (⌘L, ⌘R or with two fingers) and flipping affect the view only. The file stays unchanged; the next image appears as it is stored.

# Information

The sidebar shows the folders, the images as a list, the information about the image, or folders and information stacked. Switch at the top of the sidebar or with ⌃⌘1 to ⌃⌘4.

## What Motiv Shows

- File: name, kind, size and date
- Image: dimensions, colour profile and bit depth
- Capture: camera, lens, exposure and capture date
- Location, description and keywords; duration and codec for videos
- On request, all metadata of the file

## Quick Info and Maps

With ⌥⌘I, a line in the image shows the most important details. If an image holds a location, a click opens it in Maps; Motiv itself loads no map.

# Comparing

Select two to four images and press ⌃⌘C. Motiv shows them side by side, four as 2 × 2. Below each image are its letter, name, dimensions and size.

![Four images compared](docs/screenshots/en/3-compare.jpg)

## Linked Zoom

Zoom and position are linked: all images show the same area, even at different resolutions. “Same pixels” shows them all at the same scale instead; the chain symbol unlinks them.

## On Top of Each Other

- Toggle: the images in the same place, switch with the space bar or A to D
- Blend: fade smoothly from one image into the other, with the slider or ← and →
- Split: one image on the left, the other on the right, with a line you can drag

Esc ends the comparison.

# Videos and Other Apps

Motiv recognises videos and displays them with a still frame, but does not play them. A double-click opens them in your default app, such as QuickTime Player.

## Editing

Motiv never modifies any images. ⌘E opens an image in Preview, “Open With” in any other app. Sharing and copying hand over files only when you explicitly ask for it.

## Default App

If Motiv should always open images, make it the default in Settings, for all formats or one by one. macOS asks you to confirm each format. “Reset” later gives a format back to the app that had it before. Camera RAW formats are deliberately not offered.

# Settings

Settings hold only what is rarely changed. Motiv remembers the sort order, thumbnail size and sidebar by itself.

## Thumbnails

Motiv creates its thumbnails itself and does not store any copies of your images on disk. If you prefer speed, activate “Keep thumbnails in the system cache”; thumbnails will then be created by macOS Quick Look and kept in the system cache, just as it does for the Finder.

## Sensitive Content

If Sensitive Content Warning is switched on under “Privacy & Security” in System Settings, Motiv shows images that may contain sensitive content blurred until you choose “Show”. ⇧⌘U pauses this until Motiv quits. The check happens on your Mac only.

> If Communication Safety is set up for a child in Screen Time, Motiv does not show such images at all, and this cannot be paused.

# Questions and Answers

## Can I edit or rename images with Motiv?

No. Motiv is a pure viewer. To edit an image, open it in Preview or another app.

## A folder in the sidebar is greyed out.

Motiv cannot read it right now, for example because the disk is not connected or the folder was moved. Choose “Grant Access Again …” from the context menu to select it anew.

## The overview asks whether it should really show all images.

With subfolders, a folder can hold a great many images. Above 10,000, Motiv asks before reading them all.

## What happens to my images?

Nothing, except that they are displayed. Motiv never modifies your images and does not upload anything anywhere.

# Keyboard Shortcuts

The most important commands work without a mouse:

| Add folder | ⌘O |
| Open image, back to the overview | ↩, Esc |
| Previous and next image | ← and → |
| First and last image | Home, End |
| Page through the overview | Page Up, Page Down |
| Back, Forward | ⌘[, ⌘] |
| Parent folder | ⌘↑ |
| Zoom in, zoom out, actual size | ⌘+, ⌘-, ⌘0 |
| Fit to window | ⌘9 |
| Rotate left, rotate right | ⌘L, ⌘R |
| Switch the sidebar | ⌃⌘1 to ⌃⌘4 |
| Information, quick info | ⌘I, ⌥⌘I |
| Just the image in full screen | ⌥⌘F |
| Compare images | ⌃⌘C |
| Open in Preview | ⌘E |
| Show in Finder | ⇧⌘R |

# Privacy

Motiv does not transmit any data. There is no tracking, no analytics and no advertising, and the app itself never connects to the internet; only a voluntary tip goes through the App Store. Your images are accessed and displayed on your Mac only.

## What Is Stored Locally

- Your settings
- The folders you granted access to and your favourites
- The folder shown last, and the size and position of the windows

This data never leaves your Mac. Motiv keeps thumbnails and image information in memory only.

> If you like, you can support further development with a voluntary tip. It unlocks nothing: Motiv stays completely free.
