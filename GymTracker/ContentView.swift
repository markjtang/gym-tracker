//
//  ContentView.swift
//  GymTracker
//
//  Created by Mark Ang on 11/13/24.
//

import SwiftUI
import UserNotifications

// Models
struct Workout: Identifiable {
    let id = UUID()
    let name: String
    let exercises: [Exercise]
    let completed: Bool
}

struct Exercise: Identifiable {
    let id = UUID()
    let name: String
    let sets: Int
    let reps: String
    var isCompleted: Bool = false
}

struct SetData: Identifiable, Codable {
    var id: UUID
    var weight: String = ""
    var reps: String = ""
    var isCompleted: Bool = false
    var exerciseName: String
    
    init(id: UUID = UUID(), weight: String = "", reps: String = "", isCompleted: Bool = false, exerciseName: String) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.isCompleted = isCompleted
        self.exerciseName = exerciseName
    }
}

// Update the WorkoutInProgress struct to be a class that conforms to ObservableObject
class WorkoutInProgress: ObservableObject {
    @Published var currentExerciseIndex: Int = 0
    @Published var exerciseSets: [String: [SetData]] = [:] // Exercise.id: [SetData]
    
    init() {}
}

// Add this struct for timer state
class TimerManager: ObservableObject {
    @Published var timeRemaining: Int = 60
    @Published var isTimerRunning = false
    private var timer: Timer?
    private var startTime: Date?
    
    func startTimer(with seconds: Int) {
        // Stop any existing timer and notifications first
        stopTimer()
        
        isTimerRunning = true
        startTime = Date()
        timeRemaining = seconds
        
        // Schedule new notification
        scheduleNotification(seconds: seconds)
        
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self,
                      let startTime = self.startTime else { return }
                
                let elapsedTime = Int(Date().timeIntervalSince(startTime))
                self.timeRemaining = max(seconds - elapsedTime, 0)
                
                if self.timeRemaining == 0 {
                    self.stopTimer()
                }
            }
            
            RunLoop.current.add(self.timer!, forMode: .common)
        }
    }
    
    private func scheduleNotification(seconds: Int) {
        // Remove all pending notifications first
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        
        let content = UNMutableNotificationContent()
        content.title = "Rest Time is Up!"
        content.sound = UNNotificationSound(named: UNNotificationSoundName("gym_bell.wav"))
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "timer", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error)")
            }
        }
    }
    
    func stopTimer() {
        timer?.invalidate()
        timer = nil
        startTime = nil
        isTimerRunning = false
        
        // Remove pending notifications
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
    
    deinit {
        stopTimer()
    }
}

// Update WeightManager to handle completion status
class WeightManager {
    static let shared = WeightManager()
    private let defaults = UserDefaults.standard
    
    func saveWeight(exerciseName: String, setNumber: Int, weight: String) {
        let key = "weight_\(exerciseName)_set_\(setNumber)"
        defaults.set(weight, forKey: key)
    }
    
    func getLastWeight(exerciseName: String, setNumber: Int) -> String {
        let key = "weight_\(exerciseName)_set_\(setNumber)"
        return defaults.string(forKey: key) ?? ""
    }
    
    // Add completion status persistence
    func saveSetCompletion(exerciseName: String, setNumber: Int, isCompleted: Bool) {
        let key = "completion_\(exerciseName)_set_\(setNumber)"
        defaults.set(isCompleted, forKey: key)
    }
    
    func getSetCompletion(exerciseName: String, setNumber: Int) -> Bool {
        let key = "completion_\(exerciseName)_set_\(setNumber)"
        return defaults.bool(forKey: key)
    }
}

// First, let's add some custom colors
struct CustomColors {
    static let background = Color(.systemBackground)
    static let cardBackground = Color(.systemGray6)
    static let accent = Color.blue.opacity(0.8)
    static let textSecondary = Color.gray.opacity(0.8)
}

// Main Content View
struct ContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(0)
            
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(1)
            
            CoachingView()
                .tabItem {
                    Label("Coaching", systemImage: "figure.walk")
                }
                .tag(2)
            
            ProfileView()
                .tabItem {
                    Label("You", systemImage: "person")
                }
                .tag(3)
        }
    }
}

// Supporting Views
struct TodayView: View {
    @State private var workouts: [Workout] = []
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Card with updated styling
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TODAY, \(Date().formatted(.dateTime.month().day()))")
                            .foregroundColor(CustomColors.textSecondary)
                            .font(.system(size: 14, weight: .medium))
                            .textCase(.uppercase)
                        
                        Text("Hello, Mark! 👋")
                            .font(.system(size: 36, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    // Workout Cards
                    ForEach(workouts) { workout in
                        WorkoutCard(workout: workout)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                // Initialize with default workout if none selected
                if workouts.isEmpty {
                    workouts = [
                        Workout(name: "MARK ANG - LEGS", exercises: WorkoutTemplateManager.shared.templates[0].exercises, completed: false)
                    ]
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UpdateTodayWorkout"))) { notification in
                if let template = notification.object as? WorkoutTemplate {
                    workouts = [
                        Workout(name: template.name, exercises: template.exercises, completed: false)
                    ]
                }
            }
        }
    }
}

struct WorkoutCard: View {
    let workout: Workout
    @State private var isWorkoutStarted = false
    @StateObject private var workoutProgress = WorkoutInProgress()
    
    var body: some View {
        VStack(spacing: 24) {
            // Workout Header
            HStack {
                Text(workout.name)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
            }
            
            // Start Button
            NavigationLink(destination: ExerciseDetailView(workout: workout)) {
                Text("Start workout")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(CustomColors.accent)
                    .cornerRadius(28)
            }
            
            // Exercises List with updated styling
            VStack(alignment: .leading, spacing: 16) {
                ForEach(workout.exercises) { exercise in
                    ExerciseRow(exercise: exercise)
                    
                    if exercise.id != workout.exercises.last?.id {
                        Divider()
                            .background(CustomColors.textSecondary.opacity(0.3))
                    }
                }
            }
        }
        .padding(24)
        .background(CustomColors.background)
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exercise.name)
                    .font(.system(size: 17, weight: .semibold))
                Text("\(exercise.sets) sets • \(exercise.reps)")
                    .font(.system(size: 15))
                    .foregroundColor(CustomColors.textSecondary)
            }
            
            Spacer()
            
            if exercise.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.green)
            }
        }
        .frame(height: 50)
    }
}

struct HistoryView: View {
    var body: some View {
        Text("History")
    }
}

// First, let's create a WorkoutTemplate struct
struct WorkoutTemplate: Identifiable {
    let id = UUID()
    let name: String
    let exercises: [Exercise]
}

// Add this to store our workout templates
class WorkoutTemplateManager: ObservableObject {
    static let shared = WorkoutTemplateManager()
    
    let templates: [WorkoutTemplate] = [
        WorkoutTemplate(name: "MARK ANG - LEGS", exercises: [
            Exercise(name: "Smith Machine Squat", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Smith Machine Wide Squat", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Seated Leg Curl", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Leg Press", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Leg Press Wide Stance", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Narrow Stance Leg Press", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Calf Press on the Leg Press", sets: 4, reps: "12, 12, 12, 12")
        ]),
        WorkoutTemplate(name: "MARK ANG - CHEST", exercises: [
            Exercise(name: "Push Up", sets: 3, reps: "12, 12, 12"),
            Exercise(name: "Smith Machine Incline Bench Press", sets: 3, reps: "10, 10, 10"),
            Exercise(name: "Smith Machine Bench Press", sets: 3, reps: "10, 10, 10"),
            Exercise(name: "Shoulder Press Machine", sets: 3, reps: "10, 10, 10"),
            Exercise(name: "Leverage Chest Press", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Cable Single Arm Lateral Raise", sets: 4, reps: "15, 15, 15, 15"),
            Exercise(name: "Pec Deck", sets: 3, reps: "12, 12, 12"),
            Exercise(name: "Tricpes Overhead Extension with cable", sets: 4, reps: "10, 10, 10, 10"),
            Exercise(name: "Barbell Skull Crusher", sets: 4, reps: "10, 10, 10, 10"),
            Exercise(name: "Treadmill Incline Walk", sets: 1, reps: "20 min"),
        ]),
        WorkoutTemplate(name: "MARK ANG - BACK", exercises: [
            Exercise(name: "Machine Assisted Pull Up", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Lat Pulldown", sets: 3, reps: "12, 12, 12"),
            Exercise(name: "Cable Chest Supported Lat Pull", sets: 3, reps: "12, 12, 12"),
            Exercise(name: "Dumbbell Incline Row", sets: 3, reps: "12, 12, 12"),
            Exercise(name: "Seated Cable Rows", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Cable Facepull", sets: 5, reps: "12, 12, 12, 12, 12"),
            Exercise(name: "Dumbbell Lying Rear Lateral Raise", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Dumbbell Incline Seated Bicep Curl", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Barbell Standing Wide Grip Bicep Curl", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Treadmill Incline Walk", sets: 1, reps: "20 mins")
        ]),
        WorkoutTemplate(name: "MARK ANG - ABS", exercises: [
            Exercise(name: "Cable Crunch", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Air Bike", sets: 4, reps: "20, 20, 20, 20"),
            Exercise(name: "Full Moon Abs", sets: 4, reps: "12, 12, 12, 12"),
            Exercise(name: "Weighted Sit Ups with Bands", sets: 4, reps: "10, 10, 10, 10"),
            Exercise(name: "Treadmill Incline Walk", sets: 1, reps: "35 mins")
        ])
    ]
}

// Update CoachingView
struct CoachingView: View {
    @StateObject private var templateManager = WorkoutTemplateManager.shared
    @AppStorage("selectedWorkout") private var selectedWorkoutName: String = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Workout Templates")) {
                    ForEach(templateManager.templates) { template in
                        Button(action: {
                            selectedWorkoutName = template.name
                            // Post notification to update TodayView
                            NotificationCenter.default.post(
                                name: Notification.Name("UpdateTodayWorkout"),
                                object: template
                            )
                        }) {
                            HStack {
                                Text(template.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if template.name == selectedWorkoutName {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Coaching")
        }
    }
}

struct ProfileView: View {
    var body: some View {
        Text("Profile")
    }
}

// New view for exercise details
struct ExerciseDetailView: View {
    let workout: Workout
    @State private var currentExerciseIndex = 0
    @State private var exerciseData: [String: [SetData]] = [:] // Store data for all exercises
    @StateObject private var timerManager = TimerManager()
    @State private var restTime: Int = 60
    @Environment(\.dismiss) private var dismiss
    
    // Initialize sets for a specific exercise
    private static func initializeSetsForExercise(_ exercise: Exercise) -> [SetData] {
        let repsArray = exercise.reps.components(separatedBy: ", ")
        var initialSets: [SetData] = []
        
        for (index, reps) in repsArray.enumerated() {
            if index < exercise.sets {
                let setNumber = index + 1
                let weight = WeightManager.shared.getLastWeight(
                    exerciseName: exercise.name,
                    setNumber: setNumber
                )
                let isCompleted = WeightManager.shared.getSetCompletion(
                    exerciseName: exercise.name,
                    setNumber: setNumber
                )
                initialSets.append(SetData(
                    weight: weight,
                    reps: reps,
                    isCompleted: isCompleted,
                    exerciseName: exercise.name
                ))
            }
        }
        
        while initialSets.count < exercise.sets {
            let setNumber = initialSets.count + 1
            let weight = WeightManager.shared.getLastWeight(
                exerciseName: exercise.name,
                setNumber: setNumber
            )
            let isCompleted = WeightManager.shared.getSetCompletion(
                exerciseName: exercise.name,
                setNumber: setNumber
            )
            initialSets.append(SetData(
                weight: weight,
                reps: repsArray.last ?? "0",
                isCompleted: isCompleted,
                exerciseName: exercise.name
            ))
        }
        
        return initialSets
    }
    
    init(workout: Workout) {
        self.workout = workout
        
        // Initialize data for all exercises
        var initialData: [String: [SetData]] = [:]
        for exercise in workout.exercises {
            initialData[exercise.id.uuidString] = Self.initializeSetsForExercise(exercise)
        }
        _exerciseData = State(initialValue: initialData)
    }
    
    var body: some View {
        TabView(selection: $currentExerciseIndex) {
            ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, exercise in
                ExercisePageView(
                    exercise: exercise,
                    sets: Binding(
                        get: { exerciseData[exercise.id.uuidString] ?? [] },
                        set: { exerciseData[exercise.id.uuidString] = $0 }
                    ),
                    timerManager: timerManager,
                    restTime: $restTime,
                    isLastExercise: index == workout.exercises.count - 1,
                    onFinish: {
                        resetWorkoutCompletion()
                        dismiss()
                    }
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
    }
    
    // Method to reset the completion status of all sets
    private func resetWorkoutCompletion() {
        for exercise in workout.exercises {
            if var sets = exerciseData[exercise.id.uuidString] {
                for index in sets.indices {
                    sets[index].isCompleted = false
                    WeightManager.shared.saveSetCompletion(
                        exerciseName: exercise.name,
                        setNumber: index + 1, // Assuming setNumber is the index + 1
                        isCompleted: false
                    )
                }
                exerciseData[exercise.id.uuidString] = sets
            }
        }
    }
}

// New view for each exercise page
struct ExercisePageView: View {
    let exercise: Exercise
    @Binding var sets: [SetData]
    @ObservedObject var timerManager: TimerManager
    @Binding var restTime: Int
    let isLastExercise: Bool
    let onFinish: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Exercise Header
            VStack(alignment: .leading, spacing: 8) {
                Text(exercise.name)
                    .font(.system(size: 24, weight: .bold))
                Text("\(exercise.sets) sets")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            // Timer Settings
            VStack(spacing: 8) {
                Text("Rest Timer:")
                    .font(.subheadline)
                
                // Custom Segmented Control with buttons
                HStack(spacing: 0) {
                    ForEach([60, 90, 120, 150, 180], id: \.self) { seconds in
                        Button(action: {
                            restTime = seconds
                        }) {
                            Text("\(seconds)s")
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(restTime == seconds ? Color.accentColor : Color.clear)
                                .foregroundColor(restTime == seconds ? .white : .primary)
                        }
                    }
                }
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
            
            // Timer Display
            if timerManager.isTimerRunning {
                Text(timeString(from: timerManager.timeRemaining))
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(timerManager.timeRemaining < 10 ? .red : .primary)
                    .padding()
            }
            
            // Sets List
            List {
                ForEach(sets.indices, id: \.self) { index in
                    SetRow(
                        setNumber: index + 1,
                        setData: $sets[index],
                        timerManager: timerManager,
                        restTime: restTime,
                        exerciseName: exercise.name
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.immediately)
            
            // Finish Button (only on last exercise)
            if isLastExercise {
                Button(action: onFinish) {
                    Text("Finish Workout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.blue)
                        .cornerRadius(16)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// New view for individual set rows
struct SetRow: View {
    let setNumber: Int
    @Binding var setData: SetData
    @ObservedObject var timerManager: TimerManager
    let restTime: Int
    let exerciseName: String
    @FocusState private var isWeightFocused: Bool
    @FocusState private var isRepsFocused: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Just the number
            Text("\(setNumber)")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 25, alignment: .leading)
            
            // Weight Input (without label)
            HStack(spacing: 4) {
                TextField("0", text: $setData.weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isWeightFocused)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .onChange(of: setData.weight) { newValue in
                        WeightManager.shared.saveWeight(
                            exerciseName: exerciseName,
                            setNumber: setNumber,
                            weight: newValue
                        )
                    }
                
                Text("lbs")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 25, alignment: .leading)
            }
            .frame(width: 110)
            .contentShape(Rectangle())
            .onTapGesture {
                isWeightFocused = true
            }
            .onAppear {
                if setData.weight.isEmpty {
                    setData.weight = WeightManager.shared.getLastWeight(
                        exerciseName: exerciseName,
                        setNumber: setNumber
                    )
                }
            }
            
            // Reps Input (without label)
            HStack(spacing: 4) {
                TextField(setData.reps, text: $setData.reps)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isRepsFocused)
                    .frame(height: 44)
                    .padding(.horizontal, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("reps")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .leading)
            }
            .frame(width: 110)
            .contentShape(Rectangle())
            .onTapGesture {
                isRepsFocused = true
            }
            
            Spacer(minLength: 4)
            
            // Completion Button
            Button(action: {
                isWeightFocused = false
                isRepsFocused = false
                
                setData.isCompleted.toggle()
                WeightManager.shared.saveSetCompletion(
                    exerciseName: exerciseName,
                    setNumber: setNumber,
                    isCompleted: setData.isCompleted
                )
                
                if setData.isCompleted {
                    timerManager.startTimer(with: restTime)
                } else {
                    timerManager.stopTimer()
                }
            }) {
                Image(systemName: setData.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(setData.isCompleted ? .green : .gray)
                    .font(.system(size: 22))
            }
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color(.systemBackground))
        .onAppear {
            setData.isCompleted = WeightManager.shared.getSetCompletion(
                exerciseName: exerciseName,
                setNumber: setNumber
            )
        }
    }
}

#Preview {
    ContentView()
}
