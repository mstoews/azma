import SwiftUI

/// Positions AZMA is retained on. Public: anyone can read the board, and
/// signing in is what lets you save or apply.
struct JobBoardView: View {
    @Environment(AppSession.self) private var session
    @Environment(CandidateStore.self) private var candidate
    @State private var model = JobBoardModel()
    @State private var showingFilters = false

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.jobs.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = model.errorMessage, model.jobs.isEmpty {
                    EmptyStateView(
                        icon: "antenna.radiowaves.left.and.right.slash",
                        title: "The board could not be loaded",
                        message: message,
                        actionTitle: "Try again",
                        action: { Task { await model.load(reset: true) } }
                    )
                } else if model.jobs.isEmpty {
                    EmptyStateView(
                        icon: "briefcase",
                        title: model.hasFilters ? "No positions match" : "No open positions",
                        message: model.hasFilters
                            ? "Try a different sector, or clear the filters."
                            : "Searches are not always advertised. Ask us what we are working on.",
                        actionTitle: model.hasFilters ? "Clear filters" : nil,
                        action: model.hasFilters ? { Task { await model.clearFilters() } } : nil
                    )
                } else {
                    list
                }
            }
            .brandBackground()
            .navigationTitle("Positions")
            .searchable(text: $model.search, prompt: "Title, company or location")
            .onSubmit(of: .search) { Task { await model.load(reset: true) } }
            .onChange(of: model.search) { _, _ in model.scheduleSearch() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: model.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                }
            }
            .sheet(isPresented: $showingFilters) {
                JobFiltersSheet(model: model, options: session.options)
            }
            .navigationDestination(for: Job.self) { JobDetailView(job: $0) }
            .task { await model.load(reset: model.jobs.isEmpty) }
            .refreshable { await model.load(reset: true) }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    Text(model.summaryLine)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryInk)
                    Spacer()
                    if model.hasFilters {
                        Button("Clear") { Task { await model.clearFilters() } }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 8)

                ForEach(model.jobs) { job in
                    NavigationLink(value: job) {
                        JobCard(
                            job: job,
                            isSaved: candidate.savedJobIDs.contains(job.id),
                            applicationState: candidate.application(for: job.id)?.state
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, Theme.gutter)
                    .onAppear { Task { await model.loadMoreIfNeeded(current: job) } }
                }

                if model.isLoadingMore {
                    ProgressView().padding(.vertical, 12)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }
}

/// One position in the list.
struct JobCard: View {
    let job: Job
    var isSaved = false
    var applicationState: ApplicationState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(job.company)
                        .font(.subheadline)
                        .foregroundStyle(job.confidential ? Theme.secondaryInk : Theme.navy)
                }
                Spacer(minLength: 8)
                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.gold)
                }
            }

            FlowLayout(spacing: 6) {
                if !job.location.isEmpty { Chip(text: job.location, systemImage: "mappin.and.ellipse") }
                if job.remote { Chip(text: "Remote", systemImage: "wifi") }
                if !job.sector.isEmpty { Chip(text: job.sector) }
                if let salary = Format.salary(min: job.salaryMin, max: job.salaryMax, currency: job.salaryCurrency) {
                    Chip(text: salary, tint: Theme.successTint)
                }
            }

            if !job.description.isEmpty {
                Text(job.description)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryInk)
                    .lineLimit(2)
            }

            HStack {
                if let applicationState {
                    Chip(text: applicationState.label, systemImage: "checkmark.seal", tint: Theme.navy)
                }
                Spacer()
                if let published = job.publishedAt {
                    Text(Format.relative(published))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryInk)
                }
            }
        }
        .brandCard()
    }
}

/// Search, sector, type and remote — the filters the API supports.
struct JobFiltersSheet: View {
    @Bindable var model: JobBoardModel
    let options: ServerOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sector") {
                    Picker("Sector", selection: $model.sector) {
                        Text("Any sector").tag("")
                        ForEach(options.sectors, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                }
                Section("Type") {
                    Picker("Employment type", selection: $model.employmentType) {
                        Text("Any type").tag("")
                        ForEach(options.employmentTypes, id: \.self) {
                            Text(Format.employmentType($0)).tag($0)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("Remote only", isOn: $model.remoteOnly)
                }
            }
            .navigationTitle("Filter positions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        Task { await model.clearFilters() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Show results") {
                        Task { await model.load(reset: true) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

@MainActor
@Observable
final class JobBoardModel {
    var jobs: [Job] = []
    var search = ""
    var sector = "" { didSet { if sector != oldValue { Task { await load(reset: true) } } } }
    var employmentType = "" { didSet { if employmentType != oldValue { Task { await load(reset: true) } } } }
    var remoteOnly = false { didSet { if remoteOnly != oldValue { Task { await load(reset: true) } } } }

    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    var errorMessage: String?

    private let api: APIClient
    private let pageSize = 25
    private var searchTask: Task<Void, Never>?

    init(api: APIClient = .shared) {
        self.api = api
    }

    var hasFilters: Bool {
        !search.trimmed.isEmpty || !sector.isEmpty || !employmentType.isEmpty || remoteOnly
    }

    var summaryLine: String {
        switch total {
        case 0: return "No positions"
        case 1: return "1 position"
        default: return "\(total) positions"
        }
    }

    /// Debounced: typing in the search field should not fire a request per key.
    func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load(reset: true)
        }
    }

    func clearFilters() async {
        search = ""
        sector = ""
        employmentType = ""
        remoteOnly = false
        await load(reset: true)
    }

    func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await api.fetchJobs(
                search: search, sector: sector, employmentType: employmentType,
                remoteOnly: remoteOnly, limit: pageSize, offset: reset ? 0 : jobs.count
            )
            jobs = reset ? page.jobs : jobs + page.jobs
            total = page.total
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func loadMoreIfNeeded(current job: Job) async {
        guard !isLoadingMore, jobs.count < total, job.id == jobs.last?.id else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.fetchJobs(
                search: search, sector: sector, employmentType: employmentType,
                remoteOnly: remoteOnly, limit: pageSize, offset: jobs.count
            )
            let known = Set(jobs.map(\.id))
            jobs += page.jobs.filter { !known.contains($0.id) }
            total = page.total
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
