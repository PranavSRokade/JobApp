import SwiftUI

struct JobsListView: View {
    @StateObject private var vm = JobsViewModel()
    @State private var sheetToDelete: String? = nil
    @State private var showManageSheets = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.jobs.isEmpty {
                    ProgressView("Loading jobs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage {
                    ContentUnavailableView(
                        "Failed to load",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else if vm.showStarredOnly && vm.filteredJobs.isEmpty {
                    ContentUnavailableView(
                        "No starred jobs",
                        systemImage: "star",
                        description: Text("Swipe right on a job to star it")
                    )
                } else {
                    List(vm.filteredJobs) { job in
                        NavigationLink(destination: JobDetailView(job: job, sheetName: vm.sheetName, starredStore: vm.starredStore, profile: vm.selectedProfile)) {
                            JobRowView(job: job, sheetName: vm.sheetName, starredStore: vm.starredStore)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                    .searchable(text: $vm.searchText, prompt: "Search jobs…")
                }
            }
            .navigationTitle(vm.showStarredOnly ? "Starred" : "Jobs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            vm.showStarredOnly.toggle()
                        } label: {
                            Image(systemName: vm.showStarredOnly ? "star.fill" : "star")
                                .foregroundColor(vm.showStarredOnly ? .yellow : .secondary)
                        }
                        profilePicker
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if !vm.availableSheets.isEmpty {
                        sheetPicker
                    }
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showManageSheets) {
            ManageSheetsView(vm: vm)
        }
        .confirmationDialog(
            "Delete \(sheetToDelete.map { formatSheetName($0) } ?? "")?",
            isPresented: Binding(get: { sheetToDelete != nil }, set: { if !$0 { sheetToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let sheet = sheetToDelete {
                    Task { await vm.deleteSheet(sheet) }
                }
                sheetToDelete = nil
            }
            Button("Cancel", role: .cancel) { sheetToDelete = nil }
        }
    }

    private var sheetPicker: some View {
        Menu {
            ForEach(vm.availableSheets, id: \.self) { sheet in
                Menu(formatSheetName(sheet)) {
                    Button {
                        vm.selectedSheet = sheet
                    } label: {
                        Label("View", systemImage: sheet == vm.sheetName ? "checkmark" : "eye")
                    }
                    Button(role: .destructive) {
                        sheetToDelete = sheet
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            Divider()
            Button {
                showManageSheets = true
            } label: {
                Label("Manage Sheets…", systemImage: "slider.horizontal.3")
            }
        } label: {
            HStack(spacing: 3) {
                Text(vm.sheetName.map { formatSheetName($0) } ?? "Latest")
                    .font(.caption)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        }
    }

    private var profilePicker: some View {
        Menu {
            Button {
                vm.selectedProfile = "spencer"
            } label: {
                Label("Pranav", systemImage: vm.selectedProfile == "spencer" ? "checkmark" : "person")
            }
            Button {
                vm.selectedProfile = "gf"
            } label: {
                Label("Anushka", systemImage: vm.selectedProfile == "gf" ? "checkmark" : "person")
            }
        } label: {
            Label(vm.selectedProfile == "spencer" ? "Pranav" : "Anushka", systemImage: "person.circle")
        }
    }
}

// "03-42AM_18-Jun-26" → "18 Jun · 3:42 AM"
private func formatSheetName(_ raw: String) -> String {
    let pattern = /^(\d{2})-(\d{2})(AM|PM)_(\d{2})-([A-Za-z]{3})-(\d{2})$/
    guard let match = try? pattern.wholeMatch(in: raw) else { return raw }
    let (_, hh, mm, ampm, dd, month, _) = match.output
    let hour = Int(hh) ?? 0
    return "\(Int(dd) ?? 0) \(month) · \(hour):\(mm) \(ampm)"
}
